const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireMerchantAccess } = require('../utils');

const VOUCHER_FIELDS = [
  'code', 'merchant_id', 'description', 'discount_type', 'discount_value', 'max_discount',
  'min_order_amount', 'usage_limit', 'usage_limit_per_user', 'starts_at', 'ends_at', 'is_active'
];

router.get('/vouchers', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = ['is_active'];
  const params = [];
  if (req.query.merchant_id) { params.push(req.query.merchant_id); clauses.push(`merchant_id = $${params.length}`); }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM vouchers WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.post('/vouchers', asyncHandler(async (req, res) => {
  requireFields(req.body, ['code', 'discount_type', 'discount_value']);
  if (req.body.merchant_id) {
    await requireMerchantAccess(req.ctx, req.body.merchant_id);
  } else {
    requireRole(req.ctx, ['admin']); // mã toàn sàn chỉ admin tạo
  }
  const created = await db.insertRow('vouchers', pickFields(req.body, VOUCHER_FIELDS));
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/vouchers/:id', asyncHandler(async (req, res) => {
  const voucher = await db.findById('vouchers', req.params.id);
  if (!voucher) throw new ApiError('NOT_FOUND', 'Không tìm thấy mã giảm giá', 404);
  if (voucher.merchant_id) {
    await requireMerchantAccess(req.ctx, voucher.merchant_id);
  } else {
    requireRole(req.ctx, ['admin']);
  }
  const updated = await db.updateById('vouchers', req.params.id, pickFields(req.body, VOUCHER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.patch('/vouchers/:id/deactivate', asyncHandler(async (req, res) => {
  const voucher = await db.findById('vouchers', req.params.id);
  if (!voucher) throw new ApiError('NOT_FOUND', 'Không tìm thấy mã giảm giá', 404);
  if (voucher.merchant_id) {
    await requireMerchantAccess(req.ctx, voucher.merchant_id);
  } else {
    requireRole(req.ctx, ['admin']);
  }
  const updated = await db.updateById('vouchers', req.params.id, { is_active: false });
  res.json({ ok: true, data: updated });
}));

/** Kiểm tra trước khi đặt hàng: mã còn dùng được không, giảm bao nhiêu — KHÔNG trừ lượt dùng. */
router.post('/vouchers/validate', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['code', 'merchant_id', 'order_amount']);

  const voucher = await db.queryOne(`SELECT * FROM vouchers WHERE code = $1 AND is_active`, [req.body.code]);
  if (!voucher) return res.json({ ok: true, data: { valid: false, reason: 'Mã không tồn tại hoặc đã tắt' } });
  if (voucher.merchant_id && voucher.merchant_id !== req.body.merchant_id) {
    return res.json({ ok: true, data: { valid: false, reason: 'Mã không áp dụng cho cửa hàng này' } });
  }
  const now = new Date();
  if (new Date(voucher.starts_at) > now || (voucher.ends_at && new Date(voucher.ends_at) <= now)) {
    return res.json({ ok: true, data: { valid: false, reason: 'Mã chưa tới hạn hoặc đã hết hạn' } });
  }
  if (req.body.order_amount < voucher.min_order_amount) {
    return res.json({ ok: true, data: { valid: false, reason: `Chưa đạt giá trị đơn tối thiểu ${voucher.min_order_amount}` } });
  }
  if (voucher.usage_limit !== null && voucher.used_count >= voucher.usage_limit) {
    return res.json({ ok: true, data: { valid: false, reason: 'Mã đã hết lượt dùng' } });
  }
  const myRedemptions = await db.query(
    'SELECT id FROM voucher_redemptions WHERE voucher_id = $1 AND user_id = $2',
    [voucher.id, req.ctx.userId]
  );
  if (myRedemptions.length >= voucher.usage_limit_per_user) {
    return res.json({ ok: true, data: { valid: false, reason: 'Bạn đã dùng hết lượt cho mã này' } });
  }

  // deliveryFee mặc định 0 (chưa biết phí ship, vd chưa chọn địa chỉ) — khớp với cách
  // create_order() tính discount cho mã 'free_shipping' bằng đúng p_delivery_fee.
  const deliveryFee = Number(req.body.delivery_fee) || 0;
  let discount = 0;
  if (voucher.discount_type === 'percent') {
    discount = Math.round((req.body.order_amount * voucher.discount_value) / 100);
    if (voucher.max_discount) discount = Math.min(discount, voucher.max_discount);
  } else if (voucher.discount_type === 'fixed') {
    discount = voucher.discount_value;
  } else if (voucher.discount_type === 'free_shipping') {
    discount = deliveryFee;
  }
  discount = Math.min(discount, req.body.order_amount + deliveryFee); // không cho âm tiền
  res.json({ ok: true, data: { valid: true, discount_type: voucher.discount_type, estimated_discount: discount } });
}));

module.exports = router;
