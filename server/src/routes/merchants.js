const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireMerchantAccess } = require('../utils');

const MERCHANT_FIELDS = [
  'name', 'slug', 'description', 'merchant_type', 'logo_url', 'cover_url', 'phone', 'email',
  'business_license_no', 'tax_code', 'legal_doc_urls',
  'bank_name', 'bank_account_no', 'bank_account_name',
  'commission_rate', 'min_order_amount', 'avg_prep_minutes'
];

const BRANCH_FIELDS = [
  'name', 'phone', 'line1', 'ward', 'district', 'province',
  'latitude', 'longitude', 'is_main', 'is_open', 'delivery_radius_km'
];

// ---- Cửa hàng ----

router.get('/merchants', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = ['deleted_at IS NULL'];
  const params = [];

  const isPrivileged = req.ctx.authenticated && req.ctx.role === 'admin';
  if (!isPrivileged) clauses.push(`status = 'active'`);
  if (req.query.merchant_type) { params.push(req.query.merchant_type); clauses.push(`merchant_type = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`name ILIKE $${params.length}`); }

  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM merchants WHERE ${clauses.join(' AND ')} ORDER BY rating_avg DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

/** Cửa hàng của chính user hiện tại — bất kể trạng thái (draft/pending_review/active...),
 * khác với GET /merchants (chỉ trả active cho người ngoài). Phải đặt TRƯỚC route /merchants/:id
 * để Express không hiểu nhầm "mine" là 1 giá trị :id. */
router.get('/merchants/mine', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const rows = await db.query(
    'SELECT * FROM merchants WHERE owner_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: rows });
}));

// Field nhạy cảm (ngân hàng/thuế) — chỉ admin hoặc chính chủ cửa hàng mới thấy.
const SENSITIVE_MERCHANT_FIELDS = [
  'bank_name', 'bank_account_no', 'bank_account_name', 'tax_code', 'business_license_no', 'legal_doc_urls'
];

router.get('/merchants/:id', asyncHandler(async (req, res) => {
  const row = await db.queryOne('SELECT * FROM merchants WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);

  const isPrivileged = req.ctx.authenticated && (req.ctx.role === 'admin' || row.owner_id === req.ctx.userId);
  if (!isPrivileged) {
    SENSITIVE_MERCHANT_FIELDS.forEach((f) => delete row[f]);
    return res.json({ ok: true, data: row });
  }

  const [owner, branches] = await Promise.all([
    db.queryOne('SELECT id, full_name, phone, email FROM users WHERE id = $1', [row.owner_id]),
    db.query('SELECT * FROM branches WHERE merchant_id = $1 AND deleted_at IS NULL ORDER BY is_main DESC', [req.params.id])
  ]);
  res.json({ ok: true, data: { ...row, owner, branches } });
}));

router.post('/merchants', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['name', 'slug']);
  const data = pickFields(req.body, MERCHANT_FIELDS);

  // Admin tạo hộ cửa hàng cho 1 chủ có sẵn (chọn theo SĐT) — mọi role khác luôn tự làm owner.
  let ownerId = req.ctx.userId;
  if (req.ctx.role === 'admin' && req.body.owner_phone) {
    const owner = await db.queryOne('SELECT id FROM users WHERE phone = $1', [req.body.owner_phone]);
    if (!owner) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng với SĐT này', 404);
    ownerId = owner.id;
  }
  data.owner_id = ownerId;
  data.status = 'draft';
  const merchant = await db.insertRow('merchants', data);

  await db.query(`UPDATE users SET role = 'merchant_owner' WHERE id = $1 AND role = 'customer'`, [ownerId]);
  res.status(201).json({ ok: true, data: merchant });
}));

router.patch('/merchants/:id', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.id);
  const data = pickFields(req.body, MERCHANT_FIELDS);
  const updated = await db.updateById('merchants', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

router.post('/merchants/:id/submit-for-review', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.id);
  const updated = await db.updateById('merchants', req.params.id, { status: 'pending_review' });
  res.json({ ok: true, data: updated });
}));

router.post('/merchants/:id/review', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['approve']);
  const data = req.body.approve
    ? { status: 'active', standard_certified_at: req.body.certify_standard ? new Date().toISOString() : null }
    : { status: 'rejected' };
  const updated = await db.updateById('merchants', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

router.patch('/merchants/:id/pause', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.id);
  requireFields(req.body, ['paused']);
  const updated = await db.updateById('merchants', req.params.id, { status: req.body.paused ? 'paused' : 'active' });
  res.json({ ok: true, data: updated });
}));

/** Xoá mềm — giữ deleted_at vì sản phẩm/đơn hàng cũ còn trỏ tới cửa hàng này. Chỉ admin. */
router.delete('/merchants/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const existing = await db.queryOne('SELECT id FROM merchants WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!existing) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);
  const updated = await db.updateById('merchants', req.params.id, {
    deleted_at: new Date().toISOString(),
    status: 'closed'
  });
  res.json({ ok: true, data: updated });
}));

// ---- Chi nhánh ----

router.get('/merchants/:merchantId/branches', asyncHandler(async (req, res) => {
  const rows = await db.query(
    'SELECT * FROM branches WHERE merchant_id = $1 AND deleted_at IS NULL ORDER BY is_main DESC',
    [req.params.merchantId]
  );
  res.json({ ok: true, data: rows });
}));

router.get('/branches/:id', asyncHandler(async (req, res) => {
  const row = await db.queryOne('SELECT * FROM branches WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  res.json({ ok: true, data: row });
}));

router.post('/merchants/:merchantId/branches', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name', 'line1', 'province', 'latitude', 'longitude']);
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const data = pickFields(req.body, BRANCH_FIELDS);
  data.merchant_id = req.params.merchantId;
  const created = await db.insertRow('branches', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/branches/:id', asyncHandler(async (req, res) => {
  const branch = await db.queryOne('SELECT id, merchant_id FROM branches WHERE id = $1', [req.params.id]);
  if (!branch) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  await requireMerchantAccess(req.ctx, branch.merchant_id);
  const data = pickFields(req.body, BRANCH_FIELDS);
  const updated = await db.updateById('branches', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

/** Công tắc nhanh: hết hàng / nghỉ đột xuất thì tắt is_open. */
router.patch('/branches/:id/toggle-open', asyncHandler(async (req, res) => {
  requireFields(req.body, ['is_open']);
  const branch = await db.queryOne('SELECT id, merchant_id FROM branches WHERE id = $1', [req.params.id]);
  if (!branch) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  await requireMerchantAccess(req.ctx, branch.merchant_id);
  const updated = await db.updateById('branches', req.params.id, { is_open: !!req.body.is_open });
  res.json({ ok: true, data: updated });
}));

router.get('/branches/:id/hours', asyncHandler(async (req, res) => {
  const rows = await db.query('SELECT * FROM branch_hours WHERE branch_id = $1 ORDER BY weekday ASC', [req.params.id]);
  res.json({ ok: true, data: rows });
}));

router.put('/branches/:id/hours', asyncHandler(async (req, res) => {
  requireFields(req.body, ['hours']); // [{weekday, open_time, close_time}, ...]
  const branch = await db.queryOne('SELECT id, merchant_id FROM branches WHERE id = $1', [req.params.id]);
  if (!branch) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  await requireMerchantAccess(req.ctx, branch.merchant_id);

  await db.query('DELETE FROM branch_hours WHERE branch_id = $1', [req.params.id]);
  const rows = await db.insertRows(
    'branch_hours',
    req.body.hours.map((h) => ({ branch_id: req.params.id, weekday: h.weekday, open_time: h.open_time, close_time: h.close_time }))
  );
  res.json({ ok: true, data: rows });
}));

// ---- Nhân viên cửa hàng ----

router.get('/merchants/:merchantId/staff', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const rows = await db.query('SELECT * FROM merchant_staff WHERE merchant_id = $1', [req.params.merchantId]);
  res.json({ ok: true, data: rows });
}));

router.post('/merchants/:merchantId/staff', asyncHandler(async (req, res) => {
  requireFields(req.body, ['user_id']);
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const created = await db.insertRow('merchant_staff', {
    merchant_id: req.params.merchantId,
    branch_id: req.body.branch_id || null,
    user_id: req.body.user_id,
    position: req.body.position || null,
    permissions: req.body.permissions || []
  });
  await db.query(`UPDATE users SET role = 'merchant_staff' WHERE id = $1 AND role = 'customer'`, [req.body.user_id]);
  res.status(201).json({ ok: true, data: created });
}));

router.delete('/merchants/:merchantId/staff/:id', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  await db.deleteById('merchant_staff', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
