const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireOwnRow } = require('../utils');
const push = require('../push');

const ADDRESS_FIELDS = [
  'label', 'recipient_name', 'recipient_phone', 'line1', 'ward', 'district',
  'province', 'postal_code', 'latitude', 'longitude', 'note', 'is_default'
];

// Không lấy password_hash — endpoint admin trả cả cho web hiển thị nên phải loại field nhạy cảm.
const ADMIN_USER_COLUMNS = `
  id, phone, email, full_name, avatar_url, date_of_birth, role, status,
  phone_verified_at, email_verified_at, last_login_at, created_at, updated_at, deleted_at
`;
const ADMIN_USER_EDIT_FIELDS = ['full_name', 'email', 'phone', 'avatar_url', 'date_of_birth'];

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
  const clauses = ['deleted_at IS NULL'];
  const params = [];
  if (req.query.role) { params.push(req.query.role); clauses.push(`role = $${params.length}`); }
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`(full_name ILIKE $${params.length} OR phone ILIKE $${params.length})`); }
  const where = `WHERE ${clauses.join(' AND ')}`;
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT ${ADMIN_USER_COLUMNS} FROM users ${where} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.findById('users', req.params.id, ADMIN_USER_COLUMNS);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  const addresses = await db.query(
    'SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.params.id]
  );
  res.json({ ok: true, data: { ...row, addresses } });
}));

router.patch('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const data = pickFields(req.body, ADMIN_USER_EDIT_FIELDS);
  const updated = await db.updateById('users', req.params.id, data);
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

router.patch('/admin/users/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('users', req.params.id, { status: req.body.status });
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

router.patch('/admin/users/:id/role', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['role']);
  const updated = await db.updateById('users', req.params.id, { role: req.body.role });
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

/** Xoá mềm — giữ deleted_at để đơn hàng/dữ liệu cũ còn trỏ tới người này còn đọc được. */
router.delete('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await db.findById('users', req.params.id);
  if (!existing) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  const updated = await db.updateById('users', req.params.id, {
    deleted_at: new Date().toISOString(),
    status: 'banned'
  });
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
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

  // Thiết bị THẬT SỰ mới với tài khoản này (chưa từng có dòng nào) — nếu tài khoản thuộc 1
  // cửa hàng (chủ hoặc nhân viên), kiểm tra giới hạn max_devices của cửa hàng đó (tính chung
  // toàn bộ chủ + nhân viên) trước khi cho thêm, tránh nhiều thiết bị cùng nhận trùng thông
  // báo đơn hàng hoặc thiết bị test cũ chiếm chỗ mãi. Khách hàng/tài xế không bị giới hạn này.
  if (['merchant_owner', 'merchant_staff'].includes(req.ctx.role)) {
    const merchant = await db.queryOne(
      `SELECT m.id, m.max_devices FROM merchants m
        LEFT JOIN merchant_staff ms ON ms.merchant_id = m.id AND ms.user_id = $1
       WHERE (m.owner_id = $1 OR ms.user_id = $1) AND m.deleted_at IS NULL
       LIMIT 1`,
      [req.ctx.userId]
    );
    if (merchant) {
      const merchantUserIds = await push.resolveMerchantUserIds([merchant.id]);
      const devices = await db.query(
        `SELECT * FROM user_devices WHERE user_id = ANY($1::uuid[]) ORDER BY last_active_at ASC NULLS FIRST`,
        [merchantUserIds]
      );
      if (devices.length >= merchant.max_devices) {
        if (req.body.force_replace_oldest === true) {
          await db.deleteById('user_devices', devices[0].id);
        } else {
          return res.json({
            ok: true,
            data: {
              status: 'limit_reached',
              max_devices: merchant.max_devices,
              oldest_device: {
                id: devices[0].id,
                device_name: devices[0].device_name,
                platform: devices[0].platform,
                last_active_at: devices[0].last_active_at
              }
            }
          });
        }
      }
    }
  }

  data.user_id = req.ctx.userId;
  const created = await db.insertRow('user_devices', data);
  res.status(201).json({ ok: true, data: { status: 'ok', ...created } });
}));

// Gỡ 1 thiết bị khỏi danh sách — dừng gửi push tới máy đó (xoá push_token khỏi
// user_devices) và không còn hiện trong màn "Thiết bị đã đăng nhập". KHÔNG thu hồi được
// session Supabase thật của máy đó (server không tự quản lý session, xác thực hoàn toàn
// qua Supabase Auth) nên đây là "gỡ khỏi danh sách/ngừng nhận thông báo", không phải đăng
// xuất từ xa — client phải ghi rõ điều này, đừng để người dùng hiểu nhầm là ép đăng xuất.
router.delete('/devices/:id', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  await requireOwnRow('user_devices', req.params.id, req.ctx.userId, 'user_id');
  await db.deleteById('user_devices', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
