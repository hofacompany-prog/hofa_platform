const db = require('./db');
const { haversineKm } = require('./utils');
const push = require('./push');

// Công thức phí tạm thời — dễ chỉnh sau này khi có số liệu thật.
const BASE_FEE = 12000;
const PER_KM_FEE = 4000;
const AVG_SPEED_KMH = 25; // giả định tốc độ trung bình nội thành, dùng để ước lượng ETA

function computeDriverFee(distanceKm) {
  const raw = BASE_FEE + PER_KM_FEE * (distanceKm || 0);
  return Math.round(raw / 500) * 500;
}

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback 8s/25s nếu chưa
 * từng chạy migration hofa-db/41_driver_accept_sweep.sql. */
async function currentDriverAcceptSettings() {
  const row = await db.queryOne('SELECT * FROM driver_accept_settings ORDER BY updated_at DESC LIMIT 1');
  return row || { auto_accept_sweep_seconds: 8, manual_accept_sweep_seconds: 25 };
}

/** [minViTrenBalance] — tài xế phải có Ví trên (wallet='cod', xem hofa-db/69_driver_wallet_vi_
 * tren.sql) ĐỦ LỚN HƠN giá trị đơn mới được nhận, áp dụng cho MỌI loại đơn (không riêng COD) —
 * coi như tiền vốn tối thiểu trước khi chạy đơn. Tài xế chưa đủ (kể cả tài xế mới, số dư 0)
 * phải tự nạp tiền vào Ví trên ("Nạp tiền", app tài xế) trước khi nhận được đơn đầu tiên. */
async function findNearestOnlineDriver(pickupLat, pickupLng, excludeDriverIds, { minViTrenBalance = 0 } = {}) {
  const drivers = await db.query(
    `SELECT d.* FROM drivers d
       LEFT JOIN driver_wallet_balances w ON w.driver_id = d.id
      WHERE d.status = 'online' AND d.current_latitude IS NOT NULL AND d.current_longitude IS NOT NULL
        AND d.id <> ALL($1::uuid[])
        AND COALESCE(w.cod_balance, 0) > $2`,
    [excludeDriverIds, minViTrenBalance]
  );
  if (!drivers.length) return null;
  if (pickupLat == null || pickupLng == null) return drivers[0];
  drivers.forEach((d) => {
    d._distance = haversineKm(pickupLat, pickupLng, d.current_latitude, d.current_longitude);
  });
  drivers.sort((a, b) => a._distance - b._distance);
  return drivers[0];
}

/**
 * Tìm tài xế online gần chi nhánh nhất và gán cho đơn — LUÔN gửi push kèm màn nhận đơn (không
 * còn nhánh "auto_accept thì bỏ qua thẳng" như trước), chỉ khác thời lượng + hậu quả hết giờ
 * theo drivers.auto_accept của tài xế được gán (xem driver_accept_settings, admin cấu hình ở
 * "Thông số tài xế"):
 * - auto_accept=true: accept_window ngắn hơn (auto_accept_sweep_seconds) — hết giờ mà tài xế
 *   chưa trượt thì sweepExpiredOffers() tự NHẬN hộ (autoAcceptExpiredOffer).
 * - auto_accept=false: accept_window dài hơn (manual_accept_sweep_seconds) — hết giờ thì
 *   reassignAfterDecline() chuyển cho tài xế gần nhất kế tiếp, y hệt khi tài xế tự bấm Từ chối.
 * Trả về { delivery, driver } hoặc null nếu không còn tài xế nào online phù hợp.
 */
async function offerToNearestDriver(orderId, { excludeDriverIds = [] } = {}) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order) return null;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);

  const driver = await findNearestOnlineDriver(branch?.latitude ?? null, branch?.longitude ?? null, excludeDriverIds, {
    minViTrenBalance: order.total_amount
  });
  if (!driver) return null;

  const distanceKm =
    branch?.latitude != null && order.ship_latitude != null
      ? haversineKm(branch.latitude, branch.longitude, order.ship_latitude, order.ship_longitude)
      : null;
  return assignDriverAndNotify(order, driver, distanceKm);
}

/** Gán CHÍNH XÁC 1 tài xế khách đã chỉ định (đơn mua hộ — khách tự chọn ở checkout hoặc lúc
 * chọn lại sau khi tài xế trước từ chối) — không tự tìm tài xế khác nếu người này không còn
 * online HOẶC không đủ Ví trên theo giá trị đơn (xem findNearestOnlineDriver), trả về null
 * để nơi gọi tự báo lại cho khách chọn người khác. */
async function offerToSpecificDriver(orderId, driverId) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order) return null;
  const driver = await db.queryOne(
    `SELECT d.* FROM drivers d
       LEFT JOIN driver_wallet_balances w ON w.driver_id = d.id
      WHERE d.id = $1 AND d.status = 'online' AND COALESCE(w.cod_balance, 0) > $2`,
    [driverId, order.total_amount]
  );
  if (!driver) return null;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);

  const distanceKm =
    branch?.latitude != null && order.ship_latitude != null
      ? haversineKm(branch.latitude, branch.longitude, order.ship_latitude, order.ship_longitude)
      : null;
  return assignDriverAndNotify(order, driver, distanceKm);
}

/** Gán tài xế cụ thể đã xác định sẵn (order + driver + khoảng cách) — gọi RPC assign_driver,
 * chốt accept_deadline bằng now() của Postgres, gửi push mời nhận đơn. Dùng chung cho cả
 * offerToNearestDriver (tự tìm gần nhất) lẫn offerToSpecificDriver (khách tự chọn tài xế). */
async function assignDriverAndNotify(order, driver, distanceKm) {
  const driverFee = computeDriverFee(distanceKm ?? 0);
  const etaMinutes = distanceKm != null ? Math.max(1, Math.round((distanceKm / AVG_SPEED_KMH) * 60)) : null;

  const delivery = await db.callRpc('assign_driver', {
    p_order_id: order.id,
    p_driver_id: driver.id,
    p_distance_km: distanceKm,
    p_eta_minutes: etaMinutes,
    p_driver_fee: driverFee
  });

  const settings = await currentDriverAcceptSettings();
  const windowSeconds = driver.auto_accept ? settings.auto_accept_sweep_seconds : settings.manual_accept_sweep_seconds;
  // Tính accept_deadline bằng now() của Postgres (không phải Date.now() của Node) để khớp đúng
  // đồng hồ với assigned_at (cũng do Postgres set trong RPC assign_driver) — tránh lệch giờ giữa
  // 2 server (Render/Node và Supabase/Postgres) làm thanh màu phía tài xế tính sai % đã trôi qua.
  const deadlineRow = await db.queryOne(
    `UPDATE deliveries SET accept_deadline = now() + ($1 || ' seconds')::interval WHERE id = $2 RETURNING accept_deadline`,
    [windowSeconds, delivery.id]
  );
  const deadline = deadlineRow.accept_deadline.toISOString();
  await push.sendPushToUser(driver.user_id, {
    title: 'Đơn mới gần bạn!',
    body: `${order.order_code} · ${distanceKm != null ? distanceKm.toFixed(1) + ' km' : ''} · ${driverFee.toLocaleString('vi-VN')}đ — xác nhận trong ${windowSeconds}s`,
    data: {
      type: 'delivery_offer',
      delivery_id: delivery.id,
      order_id: order.id,
      accept_deadline: deadline,
      accept_window_seconds: windowSeconds
    }
  });
  return { delivery: { ...delivery, accept_deadline: deadline }, driver };
}

/** Tài xế từ chối, hoặc hết hạn accept_deadline mà TẮT "Tự động nhận đơn" — trả tài xế cũ về
 * online rồi thử gán tiếp cho tài xế gần nhất kế tiếp (loại các tài xế đã từ chối). */
async function reassignAfterDecline(deliveryId) {
  const delivery = await db.queryOne('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);
  if (!delivery || !delivery.driver_id) return null;

  await db.query(`UPDATE drivers SET status = 'online' WHERE id = $1 AND status = 'busy'`, [delivery.driver_id]);
  const declined = [...new Set([...(delivery.declined_driver_ids || []), delivery.driver_id])];
  await db.query(
    `UPDATE deliveries SET driver_id = NULL, status = 'pending', accept_deadline = NULL, declined_driver_ids = $1 WHERE id = $2`,
    [declined, deliveryId]
  );
  return offerToNearestDriver(delivery.order_id, { excludeDriverIds: declined });
}

/** Đơn mua hộ: tài xế khách CHỌN TAY từ chối/hết hạn — KHÔNG tự tìm tài xế khác như đơn thường
 * (reassignAfterDecline), mà báo lại cho khách tự chọn người khác (xem
 * push.notifyCustomerRepickDriver, routes GET /drivers/available + POST /orders/:id/select-driver
 * phía app khách). Vẫn trả tài xế cũ về online + ghi declined_driver_ids y hệt
 * reassignAfterDecline để lần chọn sau loại được người vừa từ chối. */
async function repickNeeded(deliveryId, reason) {
  const delivery = await db.queryOne('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);
  if (!delivery || !delivery.driver_id) return null;

  await db.query(`UPDATE drivers SET status = 'online' WHERE id = $1 AND status = 'busy'`, [delivery.driver_id]);
  const declined = [...new Set([...(delivery.declined_driver_ids || []), delivery.driver_id])];
  await db.query(
    `UPDATE deliveries SET driver_id = NULL, status = 'pending', accept_deadline = NULL, declined_driver_ids = $1 WHERE id = $2`,
    [declined, deliveryId]
  );
  await db.query('UPDATE orders SET selected_driver_id = NULL WHERE id = $1', [delivery.order_id]);
  await push.notifyCustomerRepickDriver(delivery.order_id, reason);
  return { needsRepick: true };
}

/** Hết hạn accept_deadline mà tài xế BẬT "Tự động nhận đơn" — tự NHẬN hộ (đối xứng với
 * reassignAfterDecline dùng khi tắt). Báo cho tài xế bằng push vì sweep này có thể chạy lúc
 * app tài xế đã đóng (client cũng chủ động gọi accept sớm hơn lúc app còn mở, xem OfferScreen
 * driver app — hàm này là lưới an toàn phía server). */
async function autoAcceptExpiredOffer(deliveryId) {
  const delivery = await db.queryOne('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);
  if (!delivery || delivery.status !== 'assigned') return null;
  const driver = await db.queryOne('SELECT * FROM drivers WHERE id = $1', [delivery.driver_id]);

  const updated = await db.callRpc('update_delivery_status', { p_delivery_id: deliveryId, p_new_status: 'accepted' });
  await db.query('UPDATE deliveries SET accept_deadline = NULL WHERE id = $1', [deliveryId]);

  if (driver?.user_id) {
    await push.sendPushToUser(driver.user_id, {
      title: 'Đơn đã tự động nhận',
      body: `Đơn đã tự nhận hộ vì bạn không phản hồi kịp — nhớ đến lấy hàng nhé!`,
      data: { type: 'delivery_assigned', delivery_id: deliveryId, order_id: delivery.order_id }
    });
  }
  push.notifyCustomerOrderStatus(delivery.order_id, 'accepted').catch(() => {});
  return updated;
}

/** Quét các delivery đang chờ xác nhận nhưng đã quá accept_deadline — gọi định kỳ từ setInterval
 * (index.js) và cũng lộ ra POST /internal/sweep-expired-offers cho 1 cron ngoài dự phòng.
 * Rẽ nhánh theo drivers.auto_accept của tài xế đang được gán: bật thì tự nhận hộ, tắt thì chuyển
 * tài xế khác — TRỪ đơn mua hộ mà khách CHỌN TAY tài xế (merchant_type=buy_on_behalf VÀ
 * o.selected_driver_id còn set), tắt thì báo khách tự chọn lại (repickNeeded) chứ không tự tìm
 * tài xế khác, vì khách đã chủ động chọn người này rồi. Đơn mua hộ mà khách chọn "để hệ thống
 * tự tìm" (selected_driver_id NULL ngay từ đầu) vẫn tự chuyển tài xế khác như đơn thường. Không
 * có cron thì hạn vẫn được chặn ở bước accept (lười kiểm tra, xem routes/deliveries.js). */
async function sweepExpiredOffers() {
  const expired = await db.query(
    `SELECT d.id, dr.auto_accept, m.merchant_type, o.selected_driver_id
       FROM deliveries d
       JOIN drivers dr ON dr.id = d.driver_id
       JOIN orders o ON o.id = d.order_id
       JOIN merchants m ON m.id = o.merchant_id
      WHERE d.status = 'assigned' AND d.accept_deadline IS NOT NULL AND d.accept_deadline < now()`
  );
  const results = [];
  for (const row of expired) {
    if (row.auto_accept) {
      results.push(await autoAcceptExpiredOffer(row.id));
    } else if (row.merchant_type === 'buy_on_behalf' && row.selected_driver_id != null) {
      results.push(await repickNeeded(row.id, 'Tài xế bạn chọn không xác nhận kịp thời gian'));
    } else {
      results.push(await reassignAfterDecline(row.id));
    }
  }
  return { swept: expired.length, results };
}

module.exports = {
  offerToNearestDriver,
  offerToSpecificDriver,
  reassignAfterDecline,
  repickNeeded,
  autoAcceptExpiredOffer,
  sweepExpiredOffers,
  computeDriverFee
};
