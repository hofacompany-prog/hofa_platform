const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');
const dispatch = require('../dispatch');
const config = require('../config');
const push = require('../push');

async function requireOwnDriverRow(ctx) {
  requireRole(ctx, ['driver']);
  const driver = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [ctx.userId]);
  if (!driver) throw new ApiError('NOT_FOUND', 'Bạn chưa có hồ sơ tài xế', 404);
  return driver;
}

async function requireOwnDelivery(ctx, deliveryId) {
  const driver = await requireOwnDriverRow(ctx);
  const delivery = await db.findById('deliveries', deliveryId);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  if (delivery.driver_id !== driver.id) throw new ApiError('FORBIDDEN', 'Chuyến này không phải của bạn', 403);
  return delivery;
}

router.get('/orders/:orderId/delivery', asyncHandler(async (req, res) => {
  await requireOrderAccess(req.ctx, req.params.orderId);
  const row = await db.queryOne('SELECT * FROM deliveries WHERE order_id = $1', [req.params.orderId]);
  res.json({ ok: true, data: row });
}));

/** Phải đặt TRƯỚC /deliveries/:id để Express không hiểu nhầm "mine" là 1 giá trị :id
 * (giống lưu ý ở GET /merchants/mine trong merchants.js). */
router.get('/deliveries/mine', asyncHandler(async (req, res) => {
  const driver = await requireOwnDriverRow(req.ctx);
  const { limit, offset } = pagination(req.query);
  const clauses = ['driver_id = $1'];
  const params = [driver.id];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM deliveries WHERE ${clauses.join(' AND ')} ORDER BY assigned_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/deliveries/:id', asyncHandler(async (req, res) => {
  const delivery = await requireOwnDelivery(req.ctx, req.params.id);
  res.json({ ok: true, data: delivery });
}));

/** merchant (hoặc admin) gán 1 tài xế cụ thể cho đơn đã sẵn sàng lấy hàng — chọn tay. */
router.post('/orders/:orderId/assign-driver', asyncHandler(async (req, res) => {
  requireFields(req.body, ['driver_id']);
  const order = await db.findById('orders', req.params.orderId);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  await requireMerchantAccess(req.ctx, order.merchant_id);

  const delivery = await db.callRpc('assign_driver', {
    p_order_id: req.params.orderId,
    p_driver_id: req.body.driver_id,
    p_distance_km: req.body.distance_km || null,
    p_eta_minutes: req.body.eta_minutes || null,
    p_driver_fee: req.body.driver_fee || 0
  });
  res.json({ ok: true, data: delivery });
}));

/** Tự động tìm tài xế online gần nhất và gán (giống Grab/Shopee) — merchant/admin gọi
 * khi đơn đã "ready_for_pickup". Cũng được gọi tự động ở PATCH /orders/:id/status khi
 * đơn chuyển sang ready_for_pickup, endpoint này chỉ để bấm "Tìm tài xế" lại thủ công
 * nếu lần tự động đầu không tìm được ai (không có tài xế online). */
router.post('/orders/:orderId/find-driver', asyncHandler(async (req, res) => {
  const order = await db.findById('orders', req.params.orderId);
  if (!order) throw new ApiError('NOT_FOUND', 'Không tìm thấy đơn hàng', 404);
  await requireMerchantAccess(req.ctx, order.merchant_id);

  const existing = await db.queryOne('SELECT declined_driver_ids FROM deliveries WHERE order_id = $1', [req.params.orderId]);
  const result = await dispatch.offerToNearestDriver(req.params.orderId, {
    excludeDriverIds: existing?.declined_driver_ids || []
  });
  if (!result) throw new ApiError('NOT_FOUND', 'Hiện không có tài xế nào đang online', 404);
  res.json({ ok: true, data: result.delivery });
}));

/**
 * status: accepted | arrived_store | picked_up | delivering | delivered | failed
 * picked_up và delivered bắt buộc kèm otp đúng (khách đọc cho tài xế).
 */
router.patch('/deliveries/:id/status', asyncHandler(async (req, res) => {
  requireFields(req.body, ['status']);
  const delivery = await requireOwnDelivery(req.ctx, req.params.id);

  if (req.body.status === 'accepted' && delivery.accept_deadline && new Date(delivery.accept_deadline) < new Date()) {
    await dispatch.reassignAfterDecline(req.params.id);
    throw new ApiError('OFFER_EXPIRED', 'Đã quá hạn xác nhận — đơn đã được gán cho tài xế khác', 409);
  }

  const updated = await db.callRpc('update_delivery_status', {
    p_delivery_id: req.params.id,
    p_new_status: req.body.status,
    p_otp: req.body.otp || null,
    p_recipient_name: req.body.recipient_name || null,
    p_proof_photo_urls: req.body.proof_photo_urls || null,
    p_signature_url: req.body.signature_url || null,
    p_failure_reason: req.body.failure_reason || null
  });
  if (req.body.status === 'accepted') {
    await db.query('UPDATE deliveries SET accept_deadline = NULL WHERE id = $1', [req.params.id]);
  }

  // update_delivery_status (RPC) tự đồng bộ order.status = cùng tên khi picked_up/delivering/
  // delivered — báo cho khách ngay ở đây vì SQL không gọi được firebase-admin.
  push.notifyCustomerOrderStatus(delivery.order_id, req.body.status).catch((err) => {
    console.error('[push] Không báo được cho khách về chuyến giao', req.params.id, err.message);
  });

  res.json({ ok: true, data: updated });
}));

/** Tài xế chủ động từ chối đơn vừa được gán (trước khi accepted) — tự động chuyển
 * sang tài xế gần nhất kế tiếp, tài xế hiện tại trở lại online. */
router.post('/deliveries/:id/decline', asyncHandler(async (req, res) => {
  const delivery = await requireOwnDelivery(req.ctx, req.params.id);
  if (delivery.status !== 'assigned') {
    throw new ApiError('BAD_REQUEST', 'Chỉ có thể từ chối đơn chưa xác nhận', 400);
  }
  const result = await dispatch.reassignAfterDecline(req.params.id);
  res.json({ ok: true, data: { reassigned: !!result } });
}));

/** Quét các chuyến quá hạn accept_deadline và tự chuyển tài xế khác — gọi định kỳ
 * từ 1 cron ngoài (Render Cron Job, cron-job.org...) vì repo chưa có job scheduler
 * nội bộ. Bảo vệ bằng secret riêng, không dùng JWT vì đây không phải người dùng gọi. */
router.post('/internal/sweep-expired-offers', asyncHandler(async (req, res) => {
  if (!config.internalSweepSecret || req.headers['x-internal-secret'] !== config.internalSweepSecret) {
    throw new ApiError('FORBIDDEN', 'Thiếu hoặc sai secret', 403);
  }
  const result = await dispatch.sweepExpiredOffers();
  res.json({ ok: true, data: result });
}));

router.post('/deliveries/:id/tracks', asyncHandler(async (req, res) => {
  requireFields(req.body, ['latitude', 'longitude']);
  await requireOwnDelivery(req.ctx, req.params.id);
  const created = await db.insertRow('delivery_tracks', {
    delivery_id: req.params.id,
    latitude: req.body.latitude,
    longitude: req.body.longitude
  });
  res.status(201).json({ ok: true, data: created });
}));

router.get('/deliveries/:id/tracks', asyncHandler(async (req, res) => {
  const delivery = await db.findById('deliveries', req.params.id);
  if (!delivery) throw new ApiError('NOT_FOUND', 'Không tìm thấy chuyến giao hàng', 404);
  await requireOrderAccess(req.ctx, delivery.order_id); // khách/merchant/admin/chính tài xế đều xem được vệt đường
  const { limit } = pagination(req.query);
  const rows = await db.query(
    'SELECT * FROM delivery_tracks WHERE delivery_id = $1 ORDER BY recorded_at DESC LIMIT $2',
    [req.params.id, limit || 100]
  );
  res.json({ ok: true, data: rows });
}));

module.exports = router;
