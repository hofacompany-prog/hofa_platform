const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, haversineKm } = require('../utils');

router.get('/drivers/me', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  const row = await db.queryOne('SELECT * FROM drivers WHERE user_id = $1', [req.ctx.userId]);
  res.json({ ok: true, data: row });
}));

router.post('/drivers/register', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['national_id', 'license_no', 'vehicle_type', 'vehicle_plate']);

  const existing = await db.queryOne('SELECT id FROM drivers WHERE user_id = $1', [req.ctx.userId]);
  if (existing) throw new ApiError('CONFLICT', 'Bạn đã có hồ sơ tài xế', 409);

  const data = pickFields(req.body, [
    'national_id', 'license_no', 'license_expiry', 'vehicle_type', 'vehicle_plate',
    'vehicle_capacity_kg', 'document_urls'
  ]);
  data.user_id = req.ctx.userId;
  const driver = await db.insertRow('drivers', data);
  await db.query(`UPDATE users SET role = 'driver' WHERE id = $1 AND role = 'customer'`, [req.ctx.userId]);
  res.status(201).json({ ok: true, data: driver });
}));

router.patch('/drivers/me/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['status']); // offline | online | busy | on_break
  const rows = await db.query(
    'UPDATE drivers SET status = $1 WHERE user_id = $2 RETURNING *',
    [req.body.status, req.ctx.userId]
  );
  res.json({ ok: true, data: rows[0] });
}));

router.patch('/drivers/me/auto-accept', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['auto_accept']);
  const rows = await db.query(
    'UPDATE drivers SET auto_accept = $1 WHERE user_id = $2 RETURNING *',
    [!!req.body.auto_accept, req.ctx.userId]
  );
  res.json({ ok: true, data: rows[0] });
}));

router.patch('/drivers/me/location', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  requireFields(req.body, ['latitude', 'longitude']);
  await db.query(
    'UPDATE drivers SET current_latitude = $1, current_longitude = $2, location_updated_at = now() WHERE user_id = $3',
    [req.body.latitude, req.body.longitude, req.ctx.userId]
  );
  res.json({ ok: true, data: { updated: true } });
}));

/** Danh sách tài xế online, sắp theo khoảng cách gần nhất tới 1 toạ độ (vd: chi nhánh). */
router.get('/drivers/available', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['merchant_owner', 'merchant_staff', 'admin']);
  const drivers = await db.query(`SELECT * FROM drivers WHERE status = 'online'`);
  if (req.query.latitude !== undefined && req.query.longitude !== undefined) {
    const lat = parseFloat(req.query.latitude), lon = parseFloat(req.query.longitude);
    drivers.forEach((d) => {
      d.distance_km = d.current_latitude != null ? haversineKm(lat, lon, d.current_latitude, d.current_longitude) : null;
    });
    drivers.sort((a, b) => (a.distance_km ?? 1e9) - (b.distance_km ?? 1e9));
  }
  const { limit } = pagination(req.query);
  res.json({ ok: true, data: drivers.slice(0, limit) });
}));

router.get('/drivers/me/earnings', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['driver']);
  const driver = await db.queryOne(
    'SELECT wallet_balance, total_deliveries, rating_avg, rating_count, id FROM drivers WHERE user_id = $1',
    [req.ctx.userId]
  );
  const { limit } = pagination(req.query);
  const recent = await db.query(
    `SELECT driver_fee, delivered_at FROM deliveries WHERE driver_id = $1 AND status = 'delivered' ORDER BY delivered_at DESC LIMIT $2`,
    [driver.id, limit]
  );
  res.json({ ok: true, data: { summary: driver, recent_deliveries: recent } });
}));

router.get('/admin/drivers', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM drivers ${where} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.post('/admin/drivers/:id/verify', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('drivers', req.params.id, { verified_at: new Date().toISOString() });
  res.json({ ok: true, data: updated });
}));

/** Admin chỉnh tay trạng thái tài xế (offline/online/busy/on_break) — gỡ trường hợp tài xế bị
 * kẹt ở 'busy' (vd app tắt/mất mạng giữa chừng một chuyến, chuyến đã bị xoá/đổi trạng thái ở
 * màn "Chuyến giao hàng" nhưng vì lý do gì đó không tự trả tài xế về online) khiến không nhận
 * được chuyến mới — không đụng gì tới deliveries, chỉ đổi đúng cột status của drivers. */
router.patch('/admin/drivers/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('drivers', req.params.id, { status: req.body.status });
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài xế', 404);
  res.json({ ok: true, data: updated });
}));

module.exports = router;
