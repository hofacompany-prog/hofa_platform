const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireOwnRow } = require('../utils');

const ADDRESS_FIELDS = [
  'label', 'recipient_name', 'recipient_phone', 'line1', 'ward', 'district',
  'province', 'postal_code', 'latitude', 'longitude', 'note', 'is_default'
];

// ---- Hồ sơ cá nhân ----

router.get('/me', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  if (!req.ctx.profile) {
    throw new ApiError('PROFILE_NOT_FOUND', 'Đã đăng nhập nhưng chưa có hồ sơ — gọi POST /me/sync trước', 404);
  }
  res.json({ ok: true, data: req.ctx.profile });
}));

/** Gọi ngay sau lần đăng nhập/đăng ký đầu tiên qua Supabase Auth để tạo hồ sơ trong public.users. */
router.post('/me/sync', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['full_name', 'phone']);

  const existing = await db.findById('users', req.ctx.userId);
  if (existing) {
    const patch = pickFields(req.body, ['full_name', 'email', 'avatar_url', 'date_of_birth']);
    const updated = Object.keys(patch).length ? await db.updateById('users', req.ctx.userId, patch) : existing;
    return res.json({ ok: true, data: updated });
  }

  const created = await db.insertRow('users', {
    id: req.ctx.userId,
    phone: req.body.phone,
    full_name: req.body.full_name,
    email: req.body.email || null,
    role: 'customer', // nâng role phải qua action admin, không tự nhận
    status: 'active'
  });
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/me', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const data = pickFields(req.body, ['full_name', 'email', 'avatar_url', 'date_of_birth']);
  const updated = await db.updateById('users', req.ctx.userId, data);
  res.json({ ok: true, data: updated });
}));

// ---- Quản trị (admin) ----

router.get('/admin/users', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.query.role) { params.push(req.query.role); clauses.push(`role = $${params.length}`); }
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM users ${where} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.findById('users', req.params.id);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  res.json({ ok: true, data: row });
}));

router.patch('/admin/users/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('users', req.params.id, { status: req.body.status });
  res.json({ ok: true, data: updated });
}));

router.patch('/admin/users/:id/role', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['role']);
  const updated = await db.updateById('users', req.params.id, { role: req.body.role });
  res.json({ ok: true, data: updated });
}));

// ---- Địa chỉ giao hàng ----

router.get('/addresses', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const rows = await db.query(
    'SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/addresses', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['recipient_name', 'recipient_phone', 'line1', 'province']);
  const data = pickFields(req.body, ADDRESS_FIELDS);
  data.user_id = req.ctx.userId;
  const created = await db.insertRow('addresses', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/addresses/:id', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  await requireOwnRow('addresses', req.params.id, req.ctx.userId, 'user_id');
  const data = pickFields(req.body, ADDRESS_FIELDS);
  const updated = await db.updateById('addresses', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

router.delete('/addresses/:id', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  await requireOwnRow('addresses', req.params.id, req.ctx.userId, 'user_id');
  await db.deleteById('addresses', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

// ---- Thiết bị (push notification) ----

router.get('/devices', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const rows = await db.query('SELECT * FROM user_devices WHERE user_id = $1', [req.ctx.userId]);
  res.json({ ok: true, data: rows });
}));

router.post('/devices', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['device_id']);
  const existing = await db.queryOne(
    'SELECT id FROM user_devices WHERE user_id = $1 AND device_id = $2',
    [req.ctx.userId, req.body.device_id]
  );
  const data = pickFields(req.body, ['device_id', 'device_name', 'platform', 'push_token']);
  data.last_active_at = new Date().toISOString();
  if (existing) {
    const updated = await db.updateById('user_devices', existing.id, data);
    return res.json({ ok: true, data: updated });
  }
  data.user_id = req.ctx.userId;
  const created = await db.insertRow('user_devices', data);
  res.status(201).json({ ok: true, data: created });
}));

module.exports = router;
