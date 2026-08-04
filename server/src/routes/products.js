const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireRole, requireMerchantAccess } = require('../utils');

const PRODUCT_FIELDS = [
  'name', 'slug', 'description', 'sales_model', 'status', 'brand', 'unit',
  'images', 'video_url', 'tags', 'is_featured', 'merchant_category_id'
];
const MERCHANT_CATEGORY_FIELDS = ['category_id', 'name', 'sort_order', 'is_active'];
const VARIANT_FIELDS = [
  'sku', 'barcode', 'name', 'attributes', 'price', 'compare_price', 'cost_price',
  'wholesale_price', 'weight_gram', 'is_default', 'is_active'
];
const TOPPING_GROUP_FIELDS = ['name', 'is_required', 'allow_multiple', 'sort_order'];
const TOPPING_FIELDS = ['name', 'price', 'sort_order'];
const TIER_FIELDS = [
  'min_quantity', 'max_quantity', 'unit_price', 'min_days_per_week', 'unit_price_days', 'unit_price_both',
  'requires_deposit', 'deposit_percent',
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
  const created = await db.insertRow('categories', pickFields(req.body, ['parent_id', 'name', 'slug', 'icon_url', 'icon_name', 'sort_order', 'is_active']));
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/categories/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const updated = await db.updateById('categories', req.params.id, pickFields(req.body, ['parent_id', 'name', 'slug', 'icon_url', 'icon_name', 'sort_order', 'is_active']));
  res.json({ ok: true, data: updated });
}));

/** Xoá danh mục — danh mục con của nó tự chuyển thành danh mục gốc (parent_id ON DELETE
 * SET NULL), sản phẩm gắn danh mục này chỉ mất tag (ON DELETE CASCADE trên bảng nối
 * product_categories), không xoá sản phẩm. */
router.delete('/categories/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.deleteById('categories', req.params.id);
  if (!deleted) throw new ApiError('NOT_FOUND', 'Không tìm thấy danh mục', 404);
  res.json({ ok: true, data: deleted });
}));

// ---- Danh mục cửa hàng (nằm dưới 1 danh mục con hệ thống) ----
// Công khai (không cần đăng nhập) để app khách nhóm sản phẩm theo danh mục cửa hàng.

router.get('/merchant-categories', asyncHandler(async (req, res) => {
  requireFields(req.query, ['merchant_id']);
  const clauses = ['merchant_id = $1', 'is_active'];
  const params = [req.query.merchant_id];
  if (req.query.category_id) { params.push(req.query.category_id); clauses.push(`category_id = $${params.length}`); }
  const rows = await db.query(
    `SELECT * FROM merchant_categories WHERE ${clauses.join(' AND ')} ORDER BY sort_order ASC, created_at ASC`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.post('/merchant-categories', asyncHandler(async (req, res) => {
  requireFields(req.body, ['merchant_id', 'category_id', 'name']);
  await requireMerchantAccess(req.ctx, req.body.merchant_id);
  const created = await db.insertRow('merchant_categories', {
    ...pickFields(req.body, MERCHANT_CATEGORY_FIELDS),
    merchant_id: req.body.merchant_id,
  });
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/merchant-categories/:id', asyncHandler(async (req, res) => {
  const category = await db.queryOne('SELECT id, merchant_id FROM merchant_categories WHERE id = $1', [req.params.id]);
  if (!category) throw new ApiError('NOT_FOUND', 'Không tìm thấy danh mục cửa hàng', 404);
  await requireMerchantAccess(req.ctx, category.merchant_id);
  const updated = await db.updateById('merchant_categories', req.params.id, pickFields(req.body, MERCHANT_CATEGORY_FIELDS));
  res.json({ ok: true, data: updated });
}));

/** Xoá — sản phẩm đang gắn danh mục này chỉ mất tag (products.merchant_category_id ON DELETE SET NULL). */
router.delete('/merchant-categories/:id', asyncHandler(async (req, res) => {
  const category = await db.queryOne('SELECT id, merchant_id FROM merchant_categories WHERE id = $1', [req.params.id]);
  if (!category) throw new ApiError('NOT_FOUND', 'Không tìm thấy danh mục cửa hàng', 404);
  await requireMerchantAccess(req.ctx, category.merchant_id);
  const deleted = await db.deleteById('merchant_categories', req.params.id);
  res.json({ ok: true, data: deleted });
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
  if (req.query.category_id) {
    params.push(req.query.category_id);
    clauses.push(`id IN (SELECT product_id FROM product_categories WHERE category_id = $${params.length})`);
  }
  if (req.query.is_featured !== undefined) {
    params.push(req.query.is_featured === 'true');
    clauses.push(`is_featured = $${params.length}`);
  }

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
  // Cho phép tạo luôn bậc giá sỉ/đặt trước theo từng biến thể ngay lúc tạo sản phẩm — lý do
  // giống topping_groups bên dưới: màn "Thêm sản phẩm" chưa có variant_id để gọi API bậc
  // giá riêng như lúc sửa sản phẩm.
  let variants = [];
  if (Array.isArray(req.body.variants) && req.body.variants.length) {
    for (const v of req.body.variants) {
      const variant = await db.insertRow('product_variants', { ...pickFields(v, VARIANT_FIELDS), product_id: product.id });
      let tiers = [];
      if (Array.isArray(v.wholesale_tiers) && v.wholesale_tiers.length) {
        tiers = await db.insertRows('wholesale_tiers', v.wholesale_tiers.map((t) => ({ ...pickFields(t, TIER_FIELDS), variant_id: variant.id })));
      }
      variants.push({ ...variant, wholesale_tiers: tiers });
    }
  }

  // Cho phép tạo luôn nhóm topping + lựa chọn bên trong ngay lúc tạo sản phẩm (màn "Thêm
  // sản phẩm" không có product_id để gọi 2 API topping riêng như lúc sửa sản phẩm).
  let toppingGroups = [];
  if (Array.isArray(req.body.topping_groups) && req.body.topping_groups.length) {
    for (const g of req.body.topping_groups) {
      const group = await db.insertRow('product_topping_groups', { ...pickFields(g, TOPPING_GROUP_FIELDS), product_id: product.id });
      let toppings = [];
      if (Array.isArray(g.toppings) && g.toppings.length) {
        toppings = await db.insertRows('product_toppings', g.toppings.map((t) => ({ ...pickFields(t, TOPPING_FIELDS), group_id: group.id })));
      }
      toppingGroups.push({ ...group, toppings });
    }
  }

  res.status(201).json({ ok: true, data: { ...product, variants, topping_groups: toppingGroups } });
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
  // Chỉ 1 biến thể mặc định / sản phẩm — đặt biến thể này làm mặc định thì tắt mặc định
  // của các biến thể còn lại.
  if (req.body.is_default === true) {
    await db.query('UPDATE product_variants SET is_default = false WHERE product_id = $1 AND id != $2', [variant.product_id, req.params.id]);
  }
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

// ---- Topping (tuỳ chọn thêm: topping, size, độ ngọt...) ----

router.get('/products/:productId/topping-groups', asyncHandler(async (req, res) => {
  const groups = await db.query(
    'SELECT * FROM product_topping_groups WHERE product_id = $1 ORDER BY sort_order ASC',
    [req.params.productId]
  );
  if (!groups.length) return res.json({ ok: true, data: [] });
  const ids = groups.map((g) => g.id);
  const toppings = await db.query(
    'SELECT * FROM product_toppings WHERE group_id = ANY($1::uuid[]) ORDER BY sort_order ASC',
    [ids]
  );
  const byGroup = {};
  toppings.forEach((t) => { (byGroup[t.group_id] ||= []).push(t); });
  res.json({ ok: true, data: groups.map((g) => ({ ...g, toppings: byGroup[g.id] || [] })) });
}));

router.post('/products/:productId/topping-groups', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name']);
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.productId]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);

  const data = pickFields(req.body, TOPPING_GROUP_FIELDS);
  data.product_id = req.params.productId;
  const created = await db.insertRow('product_topping_groups', data);
  res.status(201).json({ ok: true, data: { ...created, toppings: [] } });
}));

router.patch('/topping-groups/:id', asyncHandler(async (req, res) => {
  const group = await db.queryOne('SELECT id, product_id FROM product_topping_groups WHERE id = $1', [req.params.id]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [group.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('product_topping_groups', req.params.id, pickFields(req.body, TOPPING_GROUP_FIELDS));
  res.json({ ok: true, data: updated });
}));

/** Xoá nhóm topping — CASCADE tự xoá luôn các lựa chọn (toppings) bên trong nhóm đó. */
router.delete('/topping-groups/:id', asyncHandler(async (req, res) => {
  const group = await db.queryOne('SELECT id, product_id FROM product_topping_groups WHERE id = $1', [req.params.id]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [group.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const deleted = await db.deleteById('product_topping_groups', req.params.id);
  res.json({ ok: true, data: deleted });
}));

router.post('/topping-groups/:groupId/toppings', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name']);
  const group = await db.queryOne('SELECT id, product_id FROM product_topping_groups WHERE id = $1', [req.params.groupId]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [group.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);

  const data = pickFields(req.body, TOPPING_FIELDS);
  data.group_id = req.params.groupId;
  const created = await db.insertRow('product_toppings', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/toppings/:id', asyncHandler(async (req, res) => {
  const topping = await db.queryOne('SELECT id, group_id FROM product_toppings WHERE id = $1', [req.params.id]);
  if (!topping) throw new ApiError('NOT_FOUND', 'Không tìm thấy topping', 404);
  const group = await db.queryOne('SELECT product_id FROM product_topping_groups WHERE id = $1', [topping.group_id]);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [group.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const updated = await db.updateById('product_toppings', req.params.id, pickFields(req.body, TOPPING_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/toppings/:id', asyncHandler(async (req, res) => {
  const topping = await db.queryOne('SELECT id, group_id FROM product_toppings WHERE id = $1', [req.params.id]);
  if (!topping) throw new ApiError('NOT_FOUND', 'Không tìm thấy topping', 404);
  const group = await db.queryOne('SELECT product_id FROM product_topping_groups WHERE id = $1', [topping.group_id]);
  const product = await db.queryOne('SELECT merchant_id FROM products WHERE id = $1', [group.product_id]);
  await requireMerchantAccess(req.ctx, product.merchant_id);
  const deleted = await db.deleteById('product_toppings', req.params.id);
  res.json({ ok: true, data: deleted });
}));

module.exports = router;
