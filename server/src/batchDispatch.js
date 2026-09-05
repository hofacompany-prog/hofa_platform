const db = require('./db');
const { routeMatrixKm } = require('./routing');

// Cùng hằng số quy đổi km↔phút với dispatch.js — giữ NHẤT QUÁN 1 công thức duy nhất cho mọi ETA
// trong hệ thống (không tạo hằng số tốc độ riêng cho ghép đơn).
const AVG_SPEED_KMH = 25;

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback tắt hẳn tính năng
 * (max_batch_orders=1) nếu chưa từng chạy migration hofa-db/107_order_batching.sql. */
async function currentBatchSettings() {
  const row = await db.queryOne('SELECT max_batch_orders, max_batch_detour_minutes FROM driver_dispatch_settings ORDER BY updated_at DESC LIMIT 1');
  return {
    maxBatchOrders: row?.max_batch_orders ?? 1,
    maxDetourMinutes: row?.max_batch_detour_minutes ?? 10
  };
}

/** Khoảng cách NHỎ NHẤT (km) đi qua hết các điểm lấy/giao trong [orders] (mảng {pickupIdx,
 * dropoffIdx}, chỉ số trỏ vào [matrix]), xuất phát từ điểm [startIdx], LUÔN ghé pickup TRƯỚC
 * dropoff của cùng 1 đơn (không ràng buộc gì giữa các đơn khác nhau — mọi cách xen kẽ đều hợp
 * lệ, đúng yêu cầu "ABCD/ABDC/BACD/BADC hoặc điểm trùng nhau"). Đệ quy chỉ sinh thứ tự HỢP LỆ
 * (không sinh tràn lan rồi lọc) — quy mô nhỏ (orders.length ≤ 5 ⇒ ≤10 điểm, ≤ 113400 thứ tự hợp
 * lệ) nên vét cạn kèm cắt tỉa (bỏ nhánh đã tệ hơn kết quả tốt nhất hiện tại) là đủ nhanh, không
 * cần heuristic. orders rỗng trả về 0 (không có gì để đi). */
function bestRouteKm(startIdx, orders, matrix) {
  if (orders.length === 0) return 0;
  let best = Infinity;

  function recurse(currentIdx, remaining, distSoFar) {
    if (distSoFar >= best) return;
    let allDone = true;
    for (let i = 0; i < remaining.length; i++) {
      const o = remaining[i];
      if (!o.pickupDone) {
        allDone = false;
        const nextIdx = o.pickupIdx;
        const next = remaining.slice();
        next[i] = { ...o, pickupDone: true };
        recurse(nextIdx, next, distSoFar + matrix[currentIdx][nextIdx]);
      } else if (!o.dropoffDone) {
        allDone = false;
        const nextIdx = o.dropoffIdx;
        const next = remaining.slice();
        next[i] = { ...o, dropoffDone: true };
        recurse(nextIdx, next, distSoFar + matrix[currentIdx][nextIdx]);
      }
    }
    if (allDone) best = Math.min(best, distSoFar);
  }

  recurse(startIdx, orders.map((o) => ({ ...o, pickupDone: false, dropoffDone: false })), 0);
  return best;
}

/** Tìm 1 tài xế ĐANG CHẠY đơn khác (đã nhận nhưng CHƯA lấy hàng — deliveries.status IN
 * ('accepted', 'arrived_store'), tức kể cả lúc đã đứng tới nơi lấy hàng nhưng chưa bấm "Đã lấy
 * hàng") phù hợp để ghép thêm [order] vào lộ trình, theo đúng điều kiện: tổng số đơn (cũ + mới)
 * không vượt max_batch_orders, và quãng đường tài xế phải đi thêm (so với chỉ chạy (các) đơn cũ
 * một mình) không vượt max_batch_detour_minutes. CHỈ gọi khi offerToNearestDriver đã tìm KHÔNG RA
 * ai hoàn toàn rảnh (xem dispatch.js) — đây là bước xen giữa "gán tài xế rảnh" và "gán tài xế dự
 * phòng rảnh"/"báo admin". Tài xế đã đứng ở điểm lấy hàng (arrived_store) vẫn tính điểm đó vào lộ
 * trình như bình thường — khoảng cách từ vị trí hiện tại (gần như trùng điểm lấy) tới chính điểm
 * đó gần 0, thuật toán tự xếp nó lên đầu lộ trình mà không cần xử lý riêng.
 *
 * [backupPool] true = xét nhóm tài xế DỰ PHÒNG đang có sẵn ≥1 đơn (dự phòng đang rảnh 0 đơn xử lý
 * ở nhánh findNearestOnlineDriver(backupPool:true) khác, không qua đây); false = xét tài xế
 * THƯỜNG đang 'busy'. Trả về { driver, pickupEtaMinutes } hoặc null nếu không ai đủ điều kiện
 * (kể cả khi tính năng đang tắt — max_batch_orders=1). */
async function findBatchableDriver(order, branch, { backupPool = false, excludeDriverIds = [] } = {}) {
  const { maxBatchOrders, maxDetourMinutes } = await currentBatchSettings();
  if (maxBatchOrders <= 1) return null;
  if (branch?.latitude == null || branch?.longitude == null || order.ship_latitude == null || order.ship_longitude == null) {
    return null; // thiếu toạ độ, không đánh giá được lộ trình — bỏ qua an toàn
  }

  const candidates = await db.query(
    backupPool
      ? `SELECT d.* FROM drivers d
           WHERE d.is_backup_driver = true
             AND d.current_latitude IS NOT NULL AND d.current_longitude IS NOT NULL
             AND d.id <> ALL($1::uuid[])
             AND EXISTS (SELECT 1 FROM deliveries del WHERE del.driver_id = d.id AND del.status IN ('accepted', 'arrived_store'))`
      : `SELECT d.* FROM drivers d
           WHERE d.status = 'busy' AND d.is_backup_driver = false
             AND d.current_latitude IS NOT NULL AND d.current_longitude IS NOT NULL
             AND d.id <> ALL($1::uuid[])`,
    [excludeDriverIds]
  );
  if (!candidates.length) return null;

  let best = null;
  for (const driver of candidates) {
    const existing = await db.query(
      `SELECT b.latitude AS pickup_lat, b.longitude AS pickup_lng,
              o.ship_latitude AS dropoff_lat, o.ship_longitude AS dropoff_lng
         FROM deliveries del
         JOIN orders o ON o.id = del.order_id
         JOIN branches b ON b.id = o.branch_id
        WHERE del.driver_id = $1 AND del.status IN ('accepted', 'arrived_store')`,
      [driver.id]
    );
    if (existing.length + 1 > maxBatchOrders) continue;
    if (existing.some((e) => e.pickup_lat == null || e.dropoff_lat == null)) continue;

    // Điểm 0 = vị trí tài xế hiện tại; kế tiếp mỗi đơn cũ 2 điểm (lấy, giao); cuối cùng đơn mới
    // 2 điểm — thứ tự này giữ nguyên khi đọc lại chỉ số ở dưới.
    const points = [{ lat: driver.current_latitude, lng: driver.current_longitude }];
    const existingOrders = [];
    for (const e of existing) {
      const pickupIdx = points.length;
      points.push({ lat: e.pickup_lat, lng: e.pickup_lng });
      const dropoffIdx = points.length;
      points.push({ lat: e.dropoff_lat, lng: e.dropoff_lng });
      existingOrders.push({ pickupIdx, dropoffIdx });
    }
    const newPickupIdx = points.length;
    points.push({ lat: branch.latitude, lng: branch.longitude });
    const newDropoffIdx = points.length;
    points.push({ lat: order.ship_latitude, lng: order.ship_longitude });

    const matrix = await routeMatrixKm(points);
    const baseKm = bestRouteKm(0, existingOrders, matrix);
    const bestKm = bestRouteKm(0, [...existingOrders, { pickupIdx: newPickupIdx, dropoffIdx: newDropoffIdx }], matrix);
    if (!Number.isFinite(bestKm)) continue;

    const extraKm = bestKm - baseKm;
    const extraMinutes = (extraKm / AVG_SPEED_KMH) * 60;
    if (extraMinutes > maxDetourMinutes) continue;

    if (!best || extraKm < best.extraKm) {
      best = { driver, extraKm, pickupDistanceKm: matrix[0][newPickupIdx] };
    }
  }
  if (!best) return null;

  const pickupEtaMinutes = Math.max(1, Math.round((best.pickupDistanceKm / AVG_SPEED_KMH) * 60));
  return { driver: best.driver, pickupEtaMinutes };
}

module.exports = { findBatchableDriver, bestRouteKm, currentBatchSettings };
