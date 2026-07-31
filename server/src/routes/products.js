const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireRole, requireMerchantAccess } = require('../utils');

const PRODUCT_FIELDS = [
  'name', 'slug', 'description', 'sales_model', 'status', 'brand', 'unit',
  'images', 'video_url', 'tags', 'is_featured'
];
const VARIANT_FIELDS = [
  'sku', 'barcode', 'name', 'attributes', 'price', 'compare_price', 'cost_price',
  'wholesale_price', 'weight_gram', 'is_default', 'is_active'
];

// ---- Danh mục ----

router.get('/categories', asyncHandler(async (req, res) => {
  const clauses = ['is_active'];
  const params = [];
  if (req.query.parent_id !== undefined) {
    if (req.query.parent_id === 'null') {
      clauses.push('parent_id IS NULL');
    } else {
      params.push(req.query.parent_id);
      clauses.push(`parent_id = $${params.length}`);
    }
  }
  const rows = await db.query(`SELECT * FROM categories WHERE ${clauses.join(' AND ')} ORDER BY sort_order ASC`, params);
  res.json({ ok: true, data: rows });
}));

router.post('/categories', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['name', 'slug']);
  const created = await db.insertRow('categories', pickFields(req.body, ['parent_id', 'name', 'slug', 'icon_url', 'sort_order', 'is_active']));
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/categories/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('categories', req.params.id, pickFields(req.body, ['parent_id', 'name', 'slug', 'icon_url', 'sort_order', 'is_active']));
  res.json({ ok: true, data: updated });
}));

// ---- Sản phẩm ----

async function attachVariants(products) {
  if (!products.length) return products;
  const ids = products.map((p) => p.id);
  const variants = await db.query(
    `SELECT * FROM product_variants WHERE product_id = ANY($1::uuid[]) AND is_active ORDER BY is_default DESC`,
    [ids]
  );
  const byProduct = {};
  variants.forEach((v) => { (byProduct[v.product_id] ||= []).push(v); });
  return products.map((p) => ({ ...p, variants: byProduct[p.id] || [] }));
}

router.get('/products', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = ['deleted_at IS NULL'];
  const params = [];

  const isOwnerViewingOwn = req.ctx.authenticated && req.query.merchant_id &&
    ['admin', 'merchant_owner', 'merchant_staff'].includes(req.ctx.role);
  if (!isOwnerViewingOwn) clauses.push(`status = 'active'`);

  if (req.query.merchant_id) { params.push(req.query.merchant_id); clauses.push(`merchant_id = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`name ILIKE $${params.length}`); }
  if (req.query.sales_model) { params.push(req.query.sales_model); clauses.push(`sales_model = $${params.length}`); }

  params.push(limit, offset);
  const rows = await db.query(
    `SELECT * FROM products WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: await attachVariants(rows) });
}));

router.get('/products/:id', asyncHandler(async (req, res) => {
  const product = await db.queryOne('SELECT * FROM products WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  const [variants, categoryLinks] = await Promise.all([
    db.query('SELECT * FROM product_variants WHERE product_id = $1 AND is_active', [req.params.id]),
    db.query('SELECT category_id FROM product_categories WHERE product_id = $1', [req.params.id])
  ]);
  res.json({ ok: true, data: { ...product, variants, category_ids: categoryLinks.map((c) => c.category_id) } });
}));

router.post('/products', asyncHandler(async (req, res) => {
  requireFields(req.body, ['merchant_id', 'name']);
  await requireMerchantAccess(req.ctx, req.body.merchant_id);

  const data = pickFields(req.body, PRODUCT_FIELDS);
  data.merchant_id = req.body.merchant_id;
  const product = await db.insertRow('products', data);

  if (Array.isArray(req.body.category_ids) && req.body.category_ids.length) {
    await db.insertRows('product_categories', req.body.category_ids.map((cid) => ({ product_id: product.id, category_id: cid })));
  }
  if (Array.isArray(req.body.variants) && req.body.variants.length) {
    await db.insertRows('product_variants', req.body.variants.map((v) => ({ ...pickFields(v, VARIANT_FIELDS), product_id: product.id })));
  }
  res.status(201).json({ ok: true, data: product });
}));

router.patch('/products/:id', asyncHandler(async (req, res) => {
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.id]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('products', req.params.id, pickFields(req.body, PRODUCT_FIELDS));
  res.json({ ok: true, data: updated });
}));

/** Xoá mềm — order_items đã chụp tên/giá riêng nên đơn cũ không bị ảnh hưởng. */
router.delete('/products/:id', asyncHandler(async (req, res) => {
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.id]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('products', req.params.id, { deleted_at: new Date().toISOString(), status: 'archived' });
  res.json({ ok: true, data: updated });
}));

router.put('/products/:id/categories', asyncHandler(async (req, res) => {
  requireFields(req.body, ['category_ids']);
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.id]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);

  await db.query('DELETE FROM product_categories WHERE product_id = $1', [req.params.id]);
  if (req.body.category_ids.length) {
    await db.insertRows('product_categories', req.body.category_ids.map((cid) => ({ product_id: req.params.id, category_id: cid })));
  }
  res.json({ ok: true, data: { updated: true } });
}));

// ---- Biến thể (giá & tồn kho nằm ở đây) ----

router.get('/products/:productId/variants', asyncHandler(async (req, res) => {
  const rows = await db.query('SELECT * FROM product_variants WHERE product_id = $1 AND is_active', [req.params.productId]);
  res.json({ ok: true, data: rows });
}));

router.post('/products/:productId/variants', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name', 'price']);
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.productId]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);

  const data = pickFields(req.body, VARIANT_FIELDS);
  data.product_id = req.params.productId;
  const created = await db.insertRow('product_variants', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/variants/:id', asyncHandler(async (req, res) => {
  const variant = await db.queryOne('SELECT id, product_id FROM product_variants WHERE id = $1', [req.params.id]);
  if (!variant) throw new ApiError('NOT_FOUND', 'Không tìm thấy biến thể', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [variant.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('product_variants', req.params.id, pickFields(req.body, VARIANT_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/variants/:id', asyncHandler(async (req, res) => {
  const variant = await db.queryOne('SELECT id, product_id FROM product_variants WHERE id = $1', [req.params.id]);
  if (!variant) throw new ApiError('NOT_FOUND', 'Không tìm thấy biến thể', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [variant.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('product_variants', req.params.id, { is_active: false });
  res.json({ ok: true, data: updated });
}));

module.exports = router;
