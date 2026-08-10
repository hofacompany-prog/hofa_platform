const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, requireMerchantAccess } = require('../utils');

const TIER_FIELDS = [
  'min_quantity', 'max_quantity', 'unit_price', 'min_days_per_week', 'unit_price_days', 'unit_price_both',
  'min_order_quantity', 'requires_deposit', 'deposit_percent',
];

async function merchantIdForVariant(variantId) {
  const variant = await db.queryOne('SELECT id, product_id FROM product_variants WHERE id = $1', [variantId]);
  if (!variant) throw new ApiError('NOT_FOUND', 'Không tìm thấy biến thể', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [variant.product_id]);
  return product.merchant_id;
}

router.get('/variants/:variantId/wholesale-tiers', asyncHandler(async (req, res) => {
  const rows = await db.query(
    'SELECT * FROM wholesale_tiers WHERE variant_id = $1 ORDER BY min_quantity ASC',
    [req.params.variantId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/variants/:variantId/wholesale-tiers', asyncHandler(async (req, res) => {
  requireFields(req.body, ['min_quantity', 'unit_price']);
  await requireMerchantAccess(req.ctx, await merchantIdForVariant(req.params.variantId));
  const data = pickFields(req.body, TIER_FIELDS);
  data.variant_id = req.params.variantId;
  const created = await db.insertRow('wholesale_tiers', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/wholesale-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, variant_id FROM wholesale_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giá', 404);
  await requireMerchantAccess(req.ctx, await merchantIdForVariant(tier.variant_id));
  const updated = await db.updateById('wholesale_tiers', req.params.id, pickFields(req.body, TIER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/wholesale-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, variant_id FROM wholesale_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giá', 404);
  await requireMerchantAccess(req.ctx, await merchantIdForVariant(tier.variant_id));
  await db.deleteById('wholesale_tiers', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

// ---- Bậc giá của biến thể MẪU (variant_templates — thư viện dùng chung của cửa hàng, xem
// products.js) — cùng cấu trúc TIER_FIELDS, CRUD y hệt wholesale_tiers ở trên. ----

async function merchantIdForTemplate(templateId) {
  const template = await db.queryOne('SELECT id, merchant_id FROM variant_templates WHERE id = $1', [templateId]);
  if (!template) throw new ApiError('NOT_FOUND', 'Không tìm thấy biến thể mẫu', 404);
  return template.merchant_id;
}

router.post('/variant-templates/:templateId/tiers', asyncHandler(async (req, res) => {
  requireFields(req.body, ['min_quantity', 'unit_price']);
  await requireMerchantAccess(req.ctx, await merchantIdForTemplate(req.params.templateId));
  const data = pickFields(req.body, TIER_FIELDS);
  data.template_id = req.params.templateId;
  const created = await db.insertRow('variant_template_tiers', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/variant-template-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, template_id FROM variant_template_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giá', 404);
  await requireMerchantAccess(req.ctx, await merchantIdForTemplate(tier.template_id));
  const updated = await db.updateById('variant_template_tiers', req.params.id, pickFields(req.body, TIER_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/variant-template-tiers/:id', asyncHandler(async (req, res) => {
  const tier = await db.queryOne('SELECT id, template_id FROM variant_template_tiers WHERE id = $1', [req.params.id]);
  if (!tier) throw new ApiError('NOT_FOUND', 'Không tìm thấy bậc giá', 404);
  await requireMerchantAccess(req.ctx, await merchantIdForTemplate(tier.template_id));
  await db.deleteById('variant_template_tiers', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
