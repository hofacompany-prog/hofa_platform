const db = require('./db');
const { haversineKm } = require('./utils');
const push = require('./push');

const ACCEPT_WINDOW_SECONDS = 25;
// Công thức phí tạm thời — dễ chỉnh sau này khi có số liệu thật.
const BASE_FEE = 12000;
const PER_KM_FEE = 4000;
const AVG_SPEED_KMH = 25; // giả định tốc độ trung bình nội thành, dùng để ước lượng ETA

function computeDriverFee(distanceKm) {
  const raw = BASE_FEE + PER_KM_FEE * (distanceKm || 0);
  return Math.round(raw / 500) * 500;
}

async function findNearestOnlineDriver(pickupLat, pickupLng, excludeDriverIds) {
  const drivers = await db.query(
    `SELECT * FROM drivers
      WHERE status = 'online' AND current_latitude IS NOT NULL AND current_longitude IS NOT NULL
        AND id <> ALL($1::uuid[])`,
    [excludeDriverIds]
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
 * Tìm tài xế online gần chi nhánh nhất và gán cho đơn.
 * - Tài xế bật auto_accept: gán thẳng, tự chuyển sang 'accepted', gửi push thông báo.
 * - Tài xế thường: gán với accept_deadline, gửi push kèm nút xác nhận/từ chối.
 * Trả về { delivery, driver } hoặc null nếu không còn tài xế nào online phù hợp.
 */
async function offerToNearestDriver(orderId, { excludeDriverIds = [] } = {}) {
  const order = await db.queryOne('SELECT * FROM orders WHERE id = $1', [orderId]);
  if (!order) return null;
  const branch = await db.queryOne('SELECT * FROM branches WHERE id = $1', [order.branch_id]);

  const driver = await findNearestOnlineDriver(branch?.latitude ?? null, branch?.longitude ?? null, excludeDriverIds);
  if (!driver) return null;

  const distanceKm =
    branch?.latitude != null && order.ship_latitude != null
      ? haversineKm(branch.latitude, branch.longitude, order.ship_latitude, order.ship_longitude)
      : null;
  const driverFee = computeDriverFee(distanceKm ?? 0);
  const etaMinutes = distanceKm != null ? Math.max(1, Math.round((distanceKm / AVG_SPEED_KMH) * 60)) : null;

  let delivery = await db.callRpc('assign_driver', {
    p_order_id: orderId,
    p_driver_id: driver.id,
    p_distance_km: distanceKm,
    p_eta_minutes: etaMinutes,
    p_driver_fee: driverFee
  });

  if (driver.auto_accept) {
    delivery = await db.callRpc('update_delivery_status', { p_delivery_id: delivery.id, p_new_status: 'accepted' });
    await push.sendPushToUser(driver.user_id, {
      title: 'Đơn mới đã tự động gán cho bạn',
      body: `${order.order_code} · ${distanceKm != null ? distanceKm.toFixed(1) + ' km' : ''} · ${driverFee.toLocaleString('vi-VN')}đ`,
      data: { type: 'delivery_assigned', delivery_id: delivery.id, order_id: orderId }
    });
    return { delivery, driver };
  }

  const deadline = new Date(Date.now() + ACCEPT_WINDOW_SECONDS * 1000).toISOString();
  await db.query('UPDATE deliveries SET accept_deadline = $1 WHERE id = $2', [deadline, delivery.id]);
  await push.sendPushToUser(driver.user_id, {
    title: 'Đơn mới gần bạn!',
    body: `${order.order_code} · ${distanceKm != null ? distanceKm.toFixed(1) + ' km' : ''} · ${driverFee.toLocaleString('vi-VN')}đ — xác nhận trong ${ACCEPT_WINDOW_SECONDS}s`,
    data: {
      type: 'delivery_offer',
      delivery_id: delivery.id,
      order_id: orderId,
      accept_deadline: deadline,
      accept_window_seconds: ACCEPT_WINDOW_SECONDS
    }
  });
  return { delivery: { ...delivery, accept_deadline: deadline }, driver };
}

/** Tài xế từ chối, hoặc hết hạn accept_deadline mà chưa xác nhận — trả tài xế cũ về
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

/** Quét các delivery đang chờ xác nhận nhưng đã quá accept_deadline — gọi định kỳ
 * từ 1 cron ngoài (xem POST /internal/sweep-expired-offers) vì repo này chưa có
 * job scheduler nội bộ. Không có cron thì hạn vẫn được chặn ở bước accept (lười kiểm tra). */
async function sweepExpiredOffers() {
  const expired = await db.query(
    `SELECT id FROM deliveries WHERE status = 'assigned' AND accept_deadline IS NOT NULL AND accept_deadline < now()`
  );
  const results = [];
  for (const row of expired) {
    results.push(await reassignAfterDecline(row.id));
  }
  return { swept: expired.length, results };
}

module.exports = { offerToNearestDriver, reassignAfterDecline, sweepExpiredOffers, computeDriverFee, ACCEPT_WINDOW_SECONDS };
