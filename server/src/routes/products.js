const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireRole, requireMerchantAccess } = require('../utils');

const PRODUCT_FIELDS = [
  'name', 'slug', 'description', 'sales_model', 'status', 'brand', 'unit', 'variant_group_name',
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
  'min_order_quantity', 'requires_deposit', 'deposit_percent',
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

// Cố ý KHÔNG có DELETE /categories/:id — danh mục ngành hàng là dữ liệu nền tảng dùng chung
// toàn sàn, xoá sẽ kéo theo mất luôn mọi merchant_categories con mà từng cửa hàng tự tạo dựa
// trên danh mục đó (ON DELETE CASCADE, xem hofa-db/01_schema.sql) — rủi ro mất dữ liệu 2 tầng
// mà admin khó lường trước. Chỉ cho sửa tên/icon (PATCH ở trên) và thêm mới (POST ở trên).

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
  if (req.query.q) {
    // Khớp tên sản phẩm HOẶC tên cửa hàng — cùng 1 tham số dùng lại 2 lần trong truy vấn,
    // Postgres cho phép tham chiếu lại placeholder đã đánh số ($N) nhiều lần.
    params.push(`%${req.query.q}%`);
    const qIdx = params.length;
    clauses.push(
      `(name ILIKE $${qIdx} OR merchant_id IN (SELECT id FROM merchants WHERE name ILIKE $${qIdx} AND deleted_at IS NULL))`
    );
  }
  if (req.query.sales_model) { params.push(req.query.sales_model); clauses.push(`sales_model = $${params.length}`); }
  if (req.query.category_id) {
    // Sản phẩm không gắn trực tiếp vào categories — suy ra qua merchant_category_id (danh
    // mục cửa hàng tự tạo, LUÔN nằm dưới đúng 1 danh mục con hệ thống, xem POST
    // /merchant-categories). Nhờ vậy admin/cửa hàng chỉ cần chọn 1 lần (danh mục cửa hàng),
    // không cần gắn thêm danh mục ngành hàng riêng cho sản phẩm.
    // category_id có thể là danh mục CHA — gộp luôn mọi danh mục CON và mọi danh mục cửa
    // hàng nằm dưới các con đó (danh mục chỉ tối đa 2 cấp nên "id = $N OR parent_id = $N"
    // luôn đủ, không cần đệ quy). Với danh mục con thì mệnh đề này tự thu về đúng 1 id, gộp
    // TẤT CẢ danh mục cửa hàng nằm dưới nó — đúng ý "vào danh mục con thì không quan tâm
    // đang thuộc danh mục cửa hàng nào".
    params.push(req.query.category_id);
    clauses.push(
      `merchant_category_id IN (SELECT id FROM merchant_categories WHERE category_id IN (SELECT id FROM categories WHERE id = $${params.length} OR parent_id = $${params.length}))`
    );
  }
  if (req.query.is_featured !== undefined) {
    params.push(req.query.is_featured === 'true');
    clauses.push(`is_featured = $${params.length}`);
  }

  params.push(limit, offset);
  const rows = await db.query(
    // id DESC làm tiebreaker — created_at không unique (nhiều sản phẩm tạo cùng lúc lúc seed
    // dữ liệu), thiếu tiebreaker thì phân trang (limit/offset) có thể lặp/bỏ sót dòng giữa các
    // trang do thứ tự trả về không ổn định.
    `SELECT * FROM products WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC, id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: await attachVariants(rows), hasMore: rows.length === limit });
}));

router.get('/products/:id', asyncHandler(async (req, res) => {
  const product = await db.queryOne('SELECT * FROM products WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  const variants = await db.query('SELECT * FROM product_variants WHERE product_id = $1 AND is_active', [req.params.id]);
  res.json({ ok: true, data: { ...product, variants } });
}));

router.post('/products', asyncHandler(async (req, res) => {
  requireFields(req.body, ['merchant_id', 'name']);
  await requireMerchantAccess(req.ctx, req.body.merchant_id);

  const data = pickFields(req.body, PRODUCT_FIELDS);
  data.merchant_id = req.body.merchant_id;
  const product = await db.insertRow('products', data);

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

  // Gắn sản phẩm vào các nhóm topping đã có sẵn của cửa hàng (thư viện dùng chung — xem
  // topping_groups bên dưới).
  if (Array.isArray(req.body.topping_group_ids) && req.body.topping_group_ids.length) {
    await db.insertRows('product_topping_group_links', req.body.topping_group_ids.map((gid) => ({ product_id: product.id, group_id: gid })));
  }

  res.status(201).json({ ok: true, data: { ...product, variants } });
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

  // Chỉ 1 biến thể mặc định / sản phẩm (idx_variants_one_default) — cùng xử lý với PATCH
  // /variants/:id bên dưới. Cần cả ở đây vì biến thể bị xoá mềm (is_active=false) vẫn còn
  // giữ is_default=true (xem DELETE /variants/:id), nếu không tắt trước thì insert biến thể
  // mặc định mới sẽ đụng unique index với hàng đã xoá mềm đó.
  if (req.body.is_default === true) {
    await db.query('UPDATE product_variants SET is_default = false WHERE product_id = $1', [req.params.productId]);
  }
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
  // Tắt luôn is_default — biến thể đã ẩn không còn là ứng viên mặc định, và giữ lại
  // is_default=true trên hàng bị xoá mềm sẽ chặn insert biến thể mặc định mới sau này
  // (idx_variants_one_default không phân biệt is_active).
  const updated = await db.updateById('product_variants', req.params.id, { is_active: false, is_default: false });
  res.json({ ok: true, data: updated });
}));

// ---- Nhóm topping (tuỳ chọn thêm: topping, size, độ ngọt...) ----
// Thư viện dùng chung của 1 cửa hàng (topping_groups.merchant_id) — tạo 1 lần, gắn được
// vào nhiều sản phẩm qua bảng nối product_topping_group_links, không phải tạo lại cho
// từng sản phẩm như trước.

async function attachToppings(groups) {
  if (!groups.length) return [];
  const ids = groups.map((g) => g.id);
  const toppings = await db.query(
    'SELECT * FROM product_toppings WHERE group_id = ANY($1::uuid[]) ORDER BY sort_order ASC',
    [ids]
  );
  const byGroup = {};
  toppings.forEach((t) => { (byGroup[t.group_id] ||= []).push(t); });
  return groups.map((g) => ({ ...g, toppings: byGroup[g.id] || [] }));
}

/** Toàn bộ nhóm topping của 1 cửa hàng, kèm số sản phẩm đang gắn mỗi nhóm — dùng cho màn
 * quản lý "Nhóm topping" và ô chọn nhóm lúc tạo/sửa sản phẩm. */
router.get('/merchants/:merchantId/topping-groups', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const groups = await db.query(
    `SELECT tg.*, COALESCE(lc.cnt, 0)::int AS linked_product_count
       FROM topping_groups tg
       LEFT JOIN (
         SELECT group_id, COUNT(*) AS cnt FROM product_topping_group_links GROUP BY group_id
       ) lc ON lc.group_id = tg.id
      WHERE tg.merchant_id = $1
      ORDER BY tg.sort_order ASC, tg.created_at ASC`,
    [req.params.merchantId]
  );
  res.json({ ok: true, data: await attachToppings(groups) });
}));

router.post('/merchants/:merchantId/topping-groups', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name']);
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const data = pickFields(req.body, TOPPING_GROUP_FIELDS);
  data.merchant_id = req.params.merchantId;
  const created = await db.insertRow('topping_groups', data);
  res.status(201).json({ ok: true, data: { ...created, toppings: [], linked_product_count: 0 } });
}));

router.get('/topping-groups/:id', asyncHandler(async (req, res) => {
  const group = await db.queryOne('SELECT * FROM topping_groups WHERE id = $1', [req.params.id]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  const [withToppings] = await attachToppings([group]);
  res.json({ ok: true, data: withToppings });
}));

router.patch('/topping-groups/:id', asyncHandler(async (req, res) => {
  const group = await db.queryOne('SELECT id, merchant_id FROM topping_groups WHERE id = $1', [req.params.id]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  await requireMerchantAccess(req.ctx, group.merchant_id);
  const updated = await db.updateById('topping_groups', req.params.id, pickFields(req.body, TOPPING_GROUP_FIELDS));
  res.json({ ok: true, data: updated });
}));

/** Xoá nhóm topping — CASCADE tự xoá luôn các lựa chọn (toppings) và liên kết với sản
 * phẩm (product_topping_group_links) đang gắn nhóm này. */
router.delete('/topping-groups/:id', asyncHandler(async (req, res) => {
  const group = await db.queryOne('SELECT id, merchant_id FROM topping_groups WHERE id = $1', [req.params.id]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  await requireMerchantAccess(req.ctx, group.merchant_id);
  const deleted = await db.deleteById('topping_groups', req.params.id);
  res.json({ ok: true, data: deleted });
}));

router.post('/topping-groups/:groupId/toppings', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name']);
  const group = await db.queryOne('SELECT id, merchant_id FROM topping_groups WHERE id = $1', [req.params.groupId]);
  if (!group) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping', 404);
  await requireMerchantAccess(req.ctx, group.merchant_id);

  const data = pickFields(req.body, TOPPING_FIELDS);
  data.group_id = req.params.groupId;
  const created = await db.insertRow('product_toppings', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/toppings/:id', asyncHandler(async (req, res) => {
  const topping = await db.queryOne('SELECT id, group_id FROM product_toppings WHERE id = $1', [req.params.id]);
  if (!topping) throw new ApiError('NOT_FOUND', 'Không tìm thấy topping', 404);
  const group = await db.queryOne('SELECT merchant_id FROM topping_groups WHERE id = $1', [topping.group_id]);
  await requireMerchantAccess(req.ctx, group.merchant_id);
  const updated = await db.updateById('product_toppings', req.params.id, pickFields(req.body, TOPPING_FIELDS));
  res.json({ ok: true, data: updated });
}));

router.delete('/toppings/:id', asyncHandler(async (req, res) => {
  const topping = await db.queryOne('SELECT id, group_id FROM product_toppings WHERE id = $1', [req.params.id]);
  if (!topping) throw new ApiError('NOT_FOUND', 'Không tìm thấy topping', 404);
  const group = await db.queryOne('SELECT merchant_id FROM topping_groups WHERE id = $1', [topping.group_id]);
  await requireMerchantAccess(req.ctx, group.merchant_id);
  const deleted = await db.deleteById('product_toppings', req.params.id);
  res.json({ ok: true, data: deleted });
}));

// ---- Gắn nhóm topping vào sản phẩm ----

/** Nhóm topping đang gắn vào 1 sản phẩm — công khai (khách xem sản phẩm cần thấy). */
router.get('/products/:productId/topping-groups', asyncHandler(async (req, res) => {
  const groups = await db.query(
    `SELECT tg.* FROM topping_groups tg
       JOIN product_topping_group_links l ON l.group_id = tg.id
      WHERE l.product_id = $1
      ORDER BY tg.sort_order ASC`,
    [req.params.productId]
  );
  res.json({ ok: true, data: await attachToppings(groups) });
}));

/** Đặt lại toàn bộ danh sách nhóm topping gắn vào 1 sản phẩm — cùng pattern với
 * PUT /products/:id/categories. */
router.put('/products/:productId/topping-groups', asyncHandler(async (req, res) => {
  requireFields(req.body, ['group_ids']);
  const product = await db.queryOne('SELECT id, merchant_id FROM products WHERE id = $1', [req.params.productId]);
  if (!product) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm', 404);
  await requireMerchantAccess(req.ctx, product.merchant_id);

  await db.query('DELETE FROM product_topping_group_links WHERE product_id = $1', [req.params.productId]);
  if (req.body.group_ids.length) {
    await db.insertRows('product_topping_group_links', req.body.group_ids.map((gid) => ({ product_id: req.params.productId, group_id: gid })));
  }
  res.json({ ok: true, data: { updated: true } });
}));

module.exports = router;
