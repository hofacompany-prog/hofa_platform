const db = require('./db');
const { routeDistanceKm, routeDistancesKm } = require('./routing');
const push = require('./push');

const AVG_SPEED_KMH = 25; // giả định tốc độ trung bình nội thành, dùng để ước lượng ETA

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback đúng giá trị mặc định
 * seed sẵn (hofa-db/16_shipping_fee_settings.sql) nếu chưa từng cấu hình. */
async function currentShippingFeeSettings() {
  const row = await db.queryOne('SELECT * FROM shipping_fee_settings ORDER BY updated_at DESC LIMIT 1');
  return row || { base_fee: 15000, base_distance_km: 2, per_km_fee: 4000, round_to: 500 };
}

/** Phí trả tài xế — dùng CHUNG base_fee/base_distance_km/per_km_fee/round_to với
 * shipping_fee_settings (đúng công thức phí ship hiện cho KHÁCH lúc đặt đơn, xem
 * hofa_customer_app/lib/models/shipping_fee_settings.dart:estimate()) để 2 bên khớp số cho
 * cùng 1 đơn — trước đây dùng hằng số riêng (BASE_FEE=12000, không có base_distance_km miễn phí)
 * lệch hẳn với cấu hình khách thấy (mặc định base_fee=15000, 2km đầu miễn phí), gây lệch tiền
 * hiển thị 2 bên tài xế/khách. CỐ Ý bỏ qua free_ship_threshold/max_fee/is_active của
 * shipping_fee_settings — đó là ưu đãi/khuyến mãi cho KHÁCH (đơn lớn miễn ship, hoặc trần phí),
 * không được làm giảm tiền tài xế thực nhận; khách được miễn/giảm ship thì HOFA tự bù, tài xế
 * vẫn nhận đúng phí theo khoảng cách thật. */
async function computeDriverFee(distanceKm) {
  const s = await currentShippingFeeSettings();
  const extraKm = Math.max(0, (distanceKm || 0) - Number(s.base_distance_km));
  const raw = Number(s.base_fee) + Number(s.per_km_fee) * extraKm;
  const roundTo = Number(s.round_to) || 500;
  return Math.round(raw / roundTo) * roundTo;
}

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback 8s/25s nếu chưa
 * từng chạy migration hofa-db/41_driver_accept_sweep.sql. */
async function currentDriverAcceptSettings() {
  const row = await db.queryOne('SELECT * FROM driver_accept_settings ORDER BY updated_at DESC LIMIT 1');
  return row || { auto_accept_sweep_seconds: 8, manual_accept_sweep_seconds: 25 };
}

/** Chỉ giữ 1 dòng đang áp dụng — dòng mới nhất theo updated_at. Fallback 60s/10 lần nếu chưa
 * từng chạy migration hofa-db/82_driver_dispatch_retry_settings.sql. */
async function currentDriverDispatchSettings() {
  const row = await db.queryOne('SELECT * FROM driver_dispatch_settings ORDER BY updated_at DESC LIMIT 1');
  return row || { rescan_interval_seconds: 60, max_rescan_attempts: 10 };
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
  // Đường đi thực tế thay vì chim bay — 1 lần gọi OSRM Table cho cả danh sách tài xế online,
  // tự rớt về haversine (từng phần tử hoặc cả danh sách) nếu OSRM lỗi/timeout, xem routing.js.
  const distances = await routeDistancesKm(
    pickupLat,
    pickupLng,
    drivers.map((d) => ({ lat: d.current_latitude, lng: d.current_longitude }))
  );
  drivers.forEach((d, i) => { d._distance = distances[i]; });
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
  const order = await db.queryOne(
    `SELECT o.*, m.merchant_type FROM orders o JOIN merchants m ON m.id = o.merchant_id WHERE o.id = $1`,
    [orderId]
  );
  if (!order) return null;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);

  const driver = await findNearestOnlineDriver(branch?.latitude ?? null, branch?.longitude ?? null, excludeDriverIds, {
    minViTrenBalance: order.total_amount
  });
  if (!driver) return null;

  const distanceKm =
    branch?.latitude != null && order.ship_latitude != null
      ? await routeDistanceKm(branch.latitude, branch.longitude, order.ship_latitude, order.ship_longitude)
      : null;
  return assignDriverAndNotify(order, driver, distanceKm);
}

/** Gán CHÍNH XÁC 1 tài xế khách đã chỉ định (đơn mua hộ — khách tự chọn ở checkout hoặc lúc
 * chọn lại sau khi tài xế trước từ chối) — không tự tìm tài xế khác nếu người này không còn
 * online HOẶC không đủ Ví trên theo giá trị đơn (xem findNearestOnlineDriver), trả về null
 * để nơi gọi tự báo lại cho khách chọn người khác. */
async function offerToSpecificDriver(orderId, driverId) {
  const order = await db.queryOne(
    `SELECT o.*, m.merchant_type FROM orders o JOIN merchants m ON m.id = o.merchant_id WHERE o.id = $1`,
    [orderId]
  );
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
      ? await routeDistanceKm(branch.latitude, branch.longitude, order.ship_latitude, order.ship_longitude)
      : null;
  return assignDriverAndNotify(order, driver, distanceKm);
}

/** Gán tài xế cụ thể đã xác định sẵn (order + driver + khoảng cách) — gọi RPC assign_driver,
 * chốt accept_deadline bằng now() của Postgres, gửi push mời nhận đơn. Dùng chung cho cả
 * offerToNearestDriver (tự tìm gần nhất) lẫn offerToSpecificDriver (khách tự chọn tài xế). */
async function assignDriverAndNotify(order, driver, distanceKm) {
  const driverFee = await computeDriverFee(distanceKm ?? 0);
  const etaMinutes = distanceKm != null ? Math.max(1, Math.round((distanceKm / AVG_SPEED_KMH) * 60)) : null;

  const delivery = await db.callRpc('assign_driver', {
    p_order_id: order.id,
    p_driver_id: driver.id,
    p_distance_km: distanceKm,
    p_eta_minutes: etaMinutes,
    p_driver_fee: driverFee
  });
  // Gán được rồi — xoá mọi dấu vết đang "chờ quét tìm tài xế" của sweepDriverSearch (nếu đơn
  // này từng bị kẹt), không riêng gì lúc chính sweep đó gán được.
  await db.query(
    `UPDATE orders SET driver_search_attempts = 0, driver_search_last_attempt_at = NULL,
       driver_search_alerted_at = NULL WHERE id = $1`,
    [order.id]
  );

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
  // Báo ngay từ tiêu đề thông báo là đơn mua hộ — tài xế cần biết TRƯỚC khi mở app ra xem chi
  // tiết (có thêm phí mua hộ, xem hofa-db/79_driver_buy_on_behalf_fee_share.sql; badge "MUA HỘ
  // +PHÍ" cạnh mã đơn ở offer_screen.dart/delivery_detail_screen.dart chỉ thấy SAU khi mở app).
  const isBuyOnBehalf = order.merchant_type === 'buy_on_behalf';
  await push.sendPushToUser(driver.user_id, {
    title: isBuyOnBehalf ? 'Đơn mới gần bạn! (Mua hộ +phí)' : 'Đơn mới gần bạn!',
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

/**
 * Quét lại các đơn ĐANG CHỜ TÀI XẾ mà lần gán gần nhất không tìm được ai (offerToNearestDriver
 * trả về null lúc chuyển ready_for_pickup, hoặc reassignAfterDecline cũng không tìm được ai
 * thay thế) — gọi định kỳ từ setInterval (index.js), tần suất quét Node cố định (15s) nhưng chỉ
 * THẬT SỰ thử gán lại cho 1 đơn khi đã đủ driver_dispatch_settings.rescan_interval_seconds kể
 * từ lần thử trước, theo đúng nhịp admin cấu hình. Chỉ áp dụng đơn "để hệ thống tự tìm"
 * (selected_driver_id IS NULL) — đơn mua hộ khách CHỌN TAY tài xế có luồng riêng
 * (repickNeeded báo khách tự chọn lại, không phải admin quyết định). Sau
 * max_rescan_attempts lần liên tiếp không tìm được ai, báo admin (notifyAdmins) quyết định
 * huỷ đơn hay quét tiếp — trong lúc chờ admin phản hồi (driver_search_alerted_at có giá trị),
 * sweep bỏ qua đơn đó, không tự quét thêm nữa.
 */
async function sweepDriverSearch() {
  const settings = await currentDriverDispatchSettings();
  const stuck = await db.query(
    `SELECT o.id, o.order_code, o.total_amount, o.driver_search_attempts, d.declined_driver_ids
       FROM orders o
       LEFT JOIN deliveries d ON d.order_id = o.id
      WHERE o.status = 'ready_for_pickup'
        AND o.selected_driver_id IS NULL
        AND o.driver_search_alerted_at IS NULL
        AND (d.id IS NULL OR (d.status = 'pending' AND d.driver_id IS NULL))
        AND (o.driver_search_last_attempt_at IS NULL
             OR o.driver_search_last_attempt_at < now() - ($1 || ' seconds')::interval)`,
    [settings.rescan_interval_seconds]
  );

  const results = [];
  for (const row of stuck) {
    // Loại các tài xế đã TỪ CHỐI chính đơn này ở lần gán trước — không mời lại người đã từ
    // chối, giống hệt reassignAfterDecline (declined_driver_ids chỉ tồn tại nếu đã từng có
    // deliveries row cho đơn này, chưa từng gán ai thì mảng rỗng).
    const assigned = await offerToNearestDriver(row.id, {
      excludeDriverIds: row.declined_driver_ids || []
    });
    if (assigned) {
      results.push({ orderId: row.id, assigned: true });
      continue;
    }

    const attempts = row.driver_search_attempts + 1;
    if (attempts >= settings.max_rescan_attempts) {
      await db.query(
        `UPDATE orders SET driver_search_attempts = $2, driver_search_last_attempt_at = now(),
           driver_search_alerted_at = now() WHERE id = $1`,
        [row.id, attempts]
      );
      await push.notifyAdmins({
        title: 'Chưa tìm được tài xế',
        body: `${row.order_code} · ${Number(row.total_amount).toLocaleString('vi-VN')}đ — đã quét ${attempts} lần không có tài xế nào nhận`,
        kind: 'driver_search_stuck',
        screen: `/orders/${row.id}`
      }).catch((err) => {
        console.error('[push] Không báo được admin cho đơn kẹt tìm tài xế', row.id, err.message);
      });
    } else {
      await db.query(
        `UPDATE orders SET driver_search_attempts = $2, driver_search_last_attempt_at = now() WHERE id = $1`,
        [row.id, attempts]
      );
    }
    results.push({ orderId: row.id, assigned: false, attempts });
  }
  return { checked: stuck.length, results };
}

module.exports = {
  offerToNearestDriver,
  offerToSpecificDriver,
  reassignAfterDecline,
  repickNeeded,
  autoAcceptExpiredOffer,
  sweepExpiredOffers,
  sweepDriverSearch,
  computeDriverFee
};
