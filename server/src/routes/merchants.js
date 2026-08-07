const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireMerchantAccess } = require('../utils');
const supabaseAdmin = require('../supabaseAdmin');
const push = require('../push');

const MERCHANT_FIELDS = [
  'name', 'slug', 'description', 'merchant_type', 'logo_url', 'cover_url', 'phone', 'email',
  'business_license_no', 'tax_code', 'legal_doc_urls',
  'bank_name', 'bank_account_no', 'bank_account_name',
  'commission_rate', 'min_order_amount', 'avg_prep_minutes',
  'buy_on_behalf_fee_basis', 'max_devices'
];

const BRANCH_FIELDS = [
  'name', 'phone', 'line1', 'ward', 'district', 'province',
  'latitude', 'longitude', 'is_main', 'is_open', 'delivery_radius_km', 'auto_accept_orders'
];

const FEE_TIER_FIELDS = [
  'min_threshold', 'max_threshold', 'fee_type', 'fee_fixed_amount', 'fee_percent'
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

  // Admin tạo hộ cửa hàng — 2 trường hợp theo SĐT (owner_phone):
  // (1) có owner_password kèm theo → chủ HOÀN TOÀN MỚI, chưa từng có tài khoản: tự tạo
  //     thẳng tài khoản Supabase Auth + public.users, không đụng gì tới tài khoản có sẵn.
  //     SĐT trùng tài khoản đã có thì báo lỗi rõ ràng để admin đổi SĐT khác, không âm thầm
  //     gắn nhầm vào tài khoản người khác.
  // (2) không có owner_password → giữ nguyên hành vi cũ: gắn vào 1 chủ đã có tài khoản sẵn.
  // Mọi role khác (không phải admin) luôn tự làm owner của chính mình.
  let ownerId = req.ctx.userId;
  if (req.ctx.role === 'admin' && req.body.owner_phone) {
    if (req.body.owner_password) {
      const existing = await db.queryOne('SELECT id FROM users WHERE phone = $1', [req.body.owner_phone]);
      if (existing) {
        throw new ApiError(
          'CONFLICT',
          'Số điện thoại này đã có tài khoản — dùng số khác, hoặc để trống mật khẩu để gắn vào tài khoản có sẵn',
          409
        );
      }
      if (String(req.body.owner_password).length < 6) {
        throw new ApiError('BAD_REQUEST', 'Mật khẩu ban đầu phải từ 6 ký tự', 400);
      }
      let authUserId;
      try {
        authUserId = await supabaseAdmin.createAuthUser(req.body.owner_phone, req.body.owner_password);
      } catch (err) {
        throw new ApiError('CONFLICT', `Không tạo được tài khoản mới: ${err.message}`, 409);
      }
      const created = await db.insertRow('users', {
        id: authUserId,
        phone: req.body.owner_phone,
        full_name: req.body.owner_full_name || req.body.name,
        role: 'customer',
        status: 'active'
      });
      ownerId = created.id;
    } else {
      const owner = await db.queryOne('SELECT id FROM users WHERE phone = $1', [req.body.owner_phone]);
      if (!owner) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng với SĐT này', 404);
      ownerId = owner.id;
    }
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

/** Đổi thẳng sang bất kỳ trạng thái nào (kể cả draft/rejected/closed) — chỉ admin.
 * Các route review/pause ở trên vẫn giữ nguyên làm lối tắt cho 2 luồng phổ biến nhất. */
router.patch('/merchants/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('merchants', req.params.id, { status: req.body.status });
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

/** Số liệu nhanh cho màn Trang chủ store app — đơn đang chuẩn bị (không tính riêng theo
 * ngày, cửa hàng cần biết đang có bao nhiêu đơn tồn đọng) và thu nhập/số đơn HÔM NAY theo
 * giờ Việt Nam (không dùng giờ server, tránh lệch múi giờ làm sai mốc "hôm nay"). Thu nhập
 * loại trừ đơn đã huỷ/hoàn tiền, số đơn "hôm nay" thì tính luôn cả đơn huỷ để đúng số đơn
 * thực nhận trong ngày (khớp cảm nhận thông thường của cửa hàng: "hôm nay có bao nhiêu đơn").
 */
router.get('/merchants/:merchantId/stats/today', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const [preparing, today] = await Promise.all([
    db.queryOne(
      `SELECT COUNT(*)::int AS count FROM orders WHERE merchant_id = $1 AND status = 'preparing'`,
      [req.params.merchantId]
    ),
    db.queryOne(
      `SELECT
         COUNT(*)::int AS order_count,
         COALESCE(SUM(total_amount) FILTER (WHERE status NOT IN ('cancelled', 'refunded')), 0)::bigint AS revenue
       FROM orders
       WHERE merchant_id = $1
         AND (created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date = (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date`,
      [req.params.merchantId]
    )
  ]);
  res.json({
    ok: true,
    data: {
      preparing_count: preparing.count,
      today_order_count: today.order_count,
      today_revenue: Number(today.revenue)
    }
  });
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

// ---- Thiết bị đăng nhập (chủ + nhân viên cùng chung 1 danh sách/1 giới hạn max_devices) ----
// Dùng ở web admin (màn chi tiết cửa hàng) để admin xem/tắt/xoá — quyền cũng cho phép chính
// chủ cửa hàng quản lý (requireMerchantAccess như mọi route khác của merchant), dù hiện tại
// store app chưa có màn nào gọi tới các route này.

router.get('/merchants/:merchantId/devices', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const userIds = await push.resolveMerchantUserIds([req.params.merchantId]);
  if (!userIds.length) return res.json({ ok: true, data: [] });
  const rows = await db.query(
    `SELECT d.*, u.full_name AS user_full_name, u.role AS user_role
       FROM user_devices d
       JOIN users u ON u.id = d.user_id
      WHERE d.user_id = ANY($1::uuid[])
      ORDER BY d.last_active_at DESC NULLS LAST`,
    [userIds]
  );
  res.json({ ok: true, data: rows });
}));

/** Chỉ "tắt" (xoá push_token, ngừng gửi thông báo tới máy đó) — giữ lại dòng để vẫn thấy
 * lịch sử đăng nhập. Không thể tự "bật" lại vì token phải do chính máy đó tạo ra. */
router.patch('/merchants/:merchantId/devices/:deviceId', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const userIds = await push.resolveMerchantUserIds([req.params.merchantId]);
  const device = await db.queryOne(
    'SELECT id FROM user_devices WHERE id = $1 AND user_id = ANY($2::uuid[])',
    [req.params.deviceId, userIds]
  );
  if (!device) throw new ApiError('NOT_FOUND', 'Không tìm thấy thiết bị', 404);
  const updated = await db.updateById('user_devices', req.params.deviceId, { push_token: null });
  res.json({ ok: true, data: updated });
}));

router.delete('/merchants/:merchantId/devices/:deviceId', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const userIds = await push.resolveMerchantUserIds([req.params.merchantId]);
  const device = await db.queryOne(
    'SELECT id FROM user_devices WHERE id = $1 AND user_id = ANY($2::uuid[])',
    [req.params.deviceId, userIds]
  );
  if (!device) throw new ApiError('NOT_FOUND', 'Không tìm thấy thiết bị', 404);
  await db.deleteById('user_devices', req.params.deviceId);
  res.json({ ok: true, data: { deleted: true } });
}));

// ---- Bậc phí mua hộ (merchant_type = 'buy_on_behalf') ----
// Khác wholesale_tiers (chủ cửa hàng tự cấu hình) — bậc phí mua hộ do ADMIN cấu hình lúc
// tạo/sửa cửa hàng ở web admin, nên chỉ admin mới được ghi; đọc thì công khai vì app khách
// cần hiển thị bảng phí ở màn sản phẩm/thanh toán trước khi đặt.

router.get('/merchants/:merchantId/fee-tiers', asyncHandler(async (req, res) => {
  const rows = await db.query(
    'SELECT * FROM merchant_fee_tiers WHERE merchant_id = $1 ORDER BY min_threshold ASC',
    [req.params.merchantId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/merchants/:merchantId/fee-tiers', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['min_threshold', 'fee_type']);
  const data = pickFields(req.body, FEE_TIER_FIELDS);
  data.merchant_id = req.params.merchantId;
  const created = await db.insertRow('merchant_fee_tiers', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/fee-tiers/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('merchant_fee_tiers', req.params.id, pickFields(req.body, FEE_TIER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/fee-tiers/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  await db.deleteById('merchant_fee_tiers', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
