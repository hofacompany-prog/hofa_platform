const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireMerchantAccess } = require('../utils');

const VOUCHER_FIELDS = [
  'code', 'merchant_id', 'description', 'discount_type', 'discount_value', 'max_discount',
  'min_order_amount', 'usage_limit', 'usage_limit_per_user', 'starts_at', 'ends_at', 'is_active',
  'is_public', 'applicable_order_kinds', 'applicable_merchant_types', 'min_concurrent_orders'
];

const TIER_FIELDS = ['min_order_amount', 'discount_value', 'max_discount'];

/** Đơn khách đang có CHƯA tới trạng thái delivering (tính cả đơn sắp tạo, +1) — dùng cho điều
 * kiện voucher min_concurrent_orders, cùng công thức với create_order() (hofa-db/
 * 50_voucher_conditions.sql) để preview ở /validate khớp với lúc đặt hàng thật. */
async function concurrentOrderCount(customerId) {
  const row = await db.queryOne(
    `SELECT COUNT(*) + 1 AS count FROM orders
      WHERE customer_id = $1 AND status NOT IN ('delivering', 'delivered', 'completed', 'cancelled', 'refunded')`,
    [customerId]
  );
  return Number(row.count);
}

/** Admin (màn quản lý voucher) thấy MỌI voucher kể cả đã tắt/hết hạn; ai khác (app khách
 * xem danh sách voucher công khai, hoặc kiểm tra mã) chỉ thấy voucher đang bật. */
router.get('/vouchers', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = [];
  const params = [];
  if (req.ctx.role !== 'admin') clauses.push('is_active');
  if (req.query.merchant_id) {
    params.push(req.query.merchant_id);
    clauses.push(`(merchant_id = $${params.length} OR merchant_id IS NULL)`);
  }
  if (req.query.is_public !== undefined) {
    params.push(req.query.is_public === 'true');
    clauses.push(`is_public = $${params.length}`);
  }
  // Lọc thêm 2 điều kiện mới cho danh sách app khách chọn — không bắt buộc, chỉ thu hẹp
  // danh sách hiện ra để khách đỡ chọn nhầm mã không dùng được (server vẫn là nơi quyết định
  // thật ở create_order(), đây chỉ là tiện lợi hiển thị).
  if (req.query.order_kind) {
    params.push(req.query.order_kind);
    clauses.push(`(applicable_order_kinds IS NULL OR $${params.length} = ANY(applicable_order_kinds))`);
  }
  if (req.query.merchant_type) {
    params.push(req.query.merchant_type);
    clauses.push(`(applicable_merchant_types IS NULL OR $${params.length} = ANY(applicable_merchant_types))`);
  }
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM vouchers ${clauses.length ? `WHERE ${clauses.join(' AND ')}` : ''} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
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
  // order_kind là preview do client tự báo (đơn thật chưa tồn tại lúc validate) — không sao vì
  // đây chỉ để xem trước, create_order() mới là nơi chốt thật dựa trên p_items thật gửi lên.
  if (voucher.applicable_order_kinds && req.body.order_kind && !voucher.applicable_order_kinds.includes(req.body.order_kind)) {
    return res.json({ ok: true, data: { valid: false, reason: 'Mã không áp dụng cho loại đơn này' } });
  }
  // merchant_type tự tra từ DB theo merchant_id, không tin client báo lên.
  if (voucher.applicable_merchant_types) {
    const merchant = await db.queryOne('SELECT merchant_type FROM merchants WHERE id = $1', [req.body.merchant_id]);
    if (!merchant || !voucher.applicable_merchant_types.includes(merchant.merchant_type)) {
      return res.json({ ok: true, data: { valid: false, reason: 'Mã không áp dụng cho loại cửa hàng này' } });
    }
  }
  if (voucher.min_concurrent_orders) {
    const concurrentCount = await concurrentOrderCount(req.ctx.userId);
    if (concurrentCount < voucher.min_concurrent_orders) {
      return res.json({
        ok: true,
        data: { valid: false, reason: `Mã yêu cầu tối thiểu ${voucher.min_concurrent_orders} đơn cùng lúc chưa giao` }
      });
    }
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
  // Bậc giảm giá theo giá trị đơn (nếu voucher có cấu hình) — chọn bậc min_order_amount cao
  // nhất đơn đạt được, khớp cách create_order() chọn (hofa-db/50_voucher_conditions.sql).
  let tierDiscountValue = null;
  let tierMaxDiscount = null;
  if (voucher.discount_type === 'percent' || voucher.discount_type === 'fixed') {
    const tier = await db.queryOne(
      `SELECT discount_value, max_discount FROM voucher_amount_tiers
        WHERE voucher_id = $1 AND min_order_amount <= $2
        ORDER BY min_order_amount DESC LIMIT 1`,
      [voucher.id, req.body.order_amount]
    );
    if (tier) {
      tierDiscountValue = tier.discount_value;
      tierMaxDiscount = tier.max_discount;
    }
  }
  let discount = 0;
  if (voucher.discount_type === 'percent') {
    const discountValue = tierDiscountValue ?? voucher.discount_value;
    const maxDiscount = tierMaxDiscount ?? voucher.max_discount;
    discount = Math.round((req.body.order_amount * discountValue) / 100);
    if (maxDiscount) discount = Math.min(discount, maxDiscount);
  } else if (voucher.discount_type === 'fixed') {
    discount = tierDiscountValue ?? voucher.discount_value;
  } else if (voucher.discount_type === 'free_shipping') {
    discount = deliveryFee;
  }
  discount = Math.min(discount, req.body.order_amount + deliveryFee); // không cho âm tiền
  res.json({ ok: true, data: { valid: true, discount_type: voucher.discount_type, estimated_discount: discount } });
}));

// ---- Bậc giảm giá theo giá trị đơn (voucher_amount_tiers) ----

async function requireVoucherAccess(ctx, voucherId) {
  const voucher = await db.findById('vouchers', voucherId);
  if (!voucher) throw new ApiError('NOT_FOUND', 'Không tìm thấy mã giảm giá', 404);
  if (voucher.merchant_id) {
    await requireMerchantAccess(ctx, voucher.merchant_id);
  } else {
    requireRole(ctx, ['admin']);
  }
  return voucher;
}

router.get('/vouchers/:voucherId/amount-tiers', asyncHandler(async (req, res) => {
  const rows = await db.query(
    'SELECT * FROM voucher_amount_tiers WHERE voucher_id = $1 ORDER BY min_order_amount ASC',
    [req.params.voucherId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/vouchers/:voucherId/amount-tiers', asyncHandler(async (req, res) => {
  requireFields(req.body, ['min_order_amount', 'discount_value']);
  await requireVoucherAccess(req.ctx, req.params.voucherId);
  const data = pickFields(req.body, TIER_FIELDS);
  data.voucher_id = req.params.voucherId;
  const created = await db.insertRow('voucher_amount_tiers', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/voucher-amount-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, voucher_id FROM voucher_amount_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giảm giá', 404);
  await requireVoucherAccess(req.ctx, tier.voucher_id);
  const updated = await db.updateById('voucher_amount_tiers', req.params.id, pickFields(req.body, TIER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/voucher-amount-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, voucher_id FROM voucher_amount_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giảm giá', 404);
  await requireVoucherAccess(req.ctx, tier.voucher_id);
  await db.deleteById('voucher_amount_tiers', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
