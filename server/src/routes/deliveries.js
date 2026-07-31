const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields, pagination, requireRole, requireMerchantAccess, requireOrderAccess } = require('../utils');

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

/** merchant (hoặc admin) gán 1 tài xế cụ thể cho đơn đã sẵn sàng lấy hàng. */
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

/**
 * status: accepted | arrived_store | picked_up | delivering | delivered | failed
 * picked_up và delivered bắt buộc kèm otp đúng (khách đọc cho tài xế).
 */
router.patch('/deliveries/:id/status', asyncHandler(async (req, res) => {
  requireFields(req.body, ['status']);
  await requireOwnDelivery(req.ctx, req.params.id);

  const updated = await db.callRpc('update_delivery_status', {
    p_delivery_id: req.params.id,
    p_new_status: req.body.status,
    p_otp: req.body.otp || null,
    p_recipient_name: req.body.recipient_name || null,
    p_proof_photo_urls: req.body.proof_photo_urls || null,
    p_signature_url: req.body.signature_url || null,
    p_failure_reason: req.body.failure_reason || null
  });
  res.json({ ok: true, data: updated });
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
