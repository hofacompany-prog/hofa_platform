const router = require('express').Router();
const crypto = require('crypto');
const db = require('../db');
const config = require('../config');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');

/**
 * Nhóm endpoint riêng cho công cụ Google Apps Script nhập liệu cửa hàng mua hộ
 * (gas/store_folder_sync.gs, tab "Đồng bộ CSDL") — KHÔNG dùng JWT (Apps Script không có
 * session Supabase), bảo vệ bằng 1 secret dùng chung, cùng pattern với
 * POST /internal/sweep-expired-offers (deliveries.js).
 *
 * An toàn cốt lõi: MỌI thao tác ghi ở đây chỉ được đụng vào cửa hàng có merchants.is_gas_synced
 * = true (tạo mới qua đây luôn tự set true) — chặn bằng WHERE/JOIN thật ở SQL, không dựa vào
 * so khớp tên, để lỡ trùng tên với 1 cửa hàng thật (tạo qua app/admin bình thường) trong sheet
 * cũng không bao giờ ghi đè nhầm.
 */
function requireGasSecret(req) {
  if (!config.gasSyncSecret || req.headers['x-gas-sync-secret'] !== config.gasSyncSecret) {
    throw new ApiError('FORBIDDEN', 'Thiếu hoặc sai secret', 403);
  }
}

function slugify(text) {
  const combiningMarks = new RegExp('[̀-ͯ]', 'g');
  const base = String(text || '')
    .normalize('NFD').replace(combiningMarks, '')
    .replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return base || 'sp';
}

/** merchants.slug UNIQUE NOT NULL — thử slug gốc trước, đụng hàng thì thêm hậu tố -2, -3... */
async function uniqueMerchantSlug(name) {
  const base = slugify(name);
  let slug = base;
  let i = 1;
  // eslint-disable-next-line no-await-in-loop
  while (await db.queryOne('SELECT id FROM merchants WHERE slug = $1', [slug])) {
    i += 1;
    slug = `${base}-${i}`;
  }
  return slug;
}

/** Cửa hàng đang thao tác PHẢI tồn tại và PHẢI do GAS quản lý — nguồn duy nhất của an toàn
 * "không ảnh hưởng cửa hàng khác" mà công cụ này cam kết. */
async function requireGasMerchant(merchantId) {
  const merchant = await db.queryOne(
    'SELECT * FROM merchants WHERE id = $1 AND is_gas_synced = true AND deleted_at IS NULL',
    [merchantId]
  );
  if (!merchant) {
    throw new ApiError(
      'FORBIDDEN',
      'Cửa hàng này không tồn tại hoặc không phải cửa hàng do GAS quản lý (is_gas_synced=false) — không được sửa qua đường đồng bộ GAS',
      403
    );
  }
  return merchant;
}

/** Toàn bộ cửa hàng do GAS quản lý (id + tên) — GAS dùng để đối chiếu với danh sách dòng còn
 * lại trong sheet MERCHANT: cửa hàng nào có ở đây mà KHÔNG còn dòng nào trong sheet trỏ đúng id
 * đó (dòng đã bị XOÁ hẳn khỏi sheet, không phải chỉ xoá tên) nghĩa là cần dọn — xem
 * DELETE /gas-sync/merchants/:id. */
router.get('/gas-sync/merchants', asyncHandler(async (req, res) => {
  requireGasSecret(req);
  const rows = await db.query(
    'SELECT id, name FROM merchants WHERE is_gas_synced = true AND deleted_at IS NULL ORDER BY name',
    []
  );
  res.json({ ok: true, data: rows });
}));

/** Xoá CỨNG 1 cửa hàng do GAS quản lý — dùng lại đúng hành vi DELETE /merchants/:id thật
 * (merchants.js: db.deleteById thẳng, không xoá mềm — quyết định có chủ đích từ migration
 * 52_merchant_hard_delete.sql, mọi FK liên quan đã CASCADE sẵn: branches, products (kéo theo
 * product_variants/product_topping_group_links), topping_groups (kéo theo product_toppings),
 * orders/payments/stock_movements...). CHỈ khác ở chỗ bắt buộc is_gas_synced=true qua
 * requireGasMerchant — không đụng được cửa hàng tạo qua app/admin bình thường. */
router.delete('/gas-sync/merchants/:id', asyncHandler(async (req, res) => {
  requireGasSecret(req);
  const merchant = await requireGasMerchant(req.params.id);
  const deleted = await db.deleteById('merchants', merchant.id);
  res.json({ ok: true, data: deleted });
}));

/** Ký request upload ảnh lên Cloudinary cho GAS — cùng cách ký với POST /uploads/cloudinary-
 * signature (uploads.js) nhưng bảo vệ bằng x-gas-sync-secret thay vì JWT (Apps Script không có
 * session Supabase để requireAuth). GAS tự POST file thẳng lên Cloudinary bằng chữ ký này, server
 * không proxy file nhị phân. */
router.post('/gas-sync/cloudinary-signature', asyncHandler(async (req, res) => {
  requireGasSecret(req);
  if (!config.cloudinaryCloudName || !config.cloudinaryApiKey || !config.cloudinaryApiSecret) {
    throw new ApiError('NOT_CONFIGURED', 'Cloudinary chưa được cấu hình trên server', 500);
  }
  const ALLOWED_FOLDERS = ['merchants', 'products'];
  const folder = ALLOWED_FOLDERS.includes(req.body.folder) ? req.body.folder : 'products';
  const timestamp = Math.round(Date.now() / 1000);
  const paramsToSign = `folder=hofa/${folder}&timestamp=${timestamp}`;
  const signature = crypto
    .createHash('sha1')
    .update(paramsToSign + config.cloudinaryApiSecret)
    .digest('hex');
  res.json({
    ok: true,
    data: {
      signature,
      timestamp,
      folder: `hofa/${folder}`,
      api_key: config.cloudinaryApiKey,
      cloud_name: config.cloudinaryCloudName
    }
  });
}));

/** Toàn bộ dữ liệu hiện có của 1 cửa hàng (do GAS quản lý) — dùng để GAS so sánh với sheet
 * trước khi đồng bộ (hiện danh sách thay đổi cho người dùng xác nhận). merchant_id trống +
 * name có giá trị = cửa hàng CHƯA từng đồng bộ, chỉ trả về cảnh báo trùng tên (nếu có), mọi
 * thứ còn lại coi như "MỚI" ở phía GAS (không cần hỏi server). */
router.get('/gas-sync/snapshot', asyncHandler(async (req, res) => {
  requireGasSecret(req);

  let merchant = null;
  if (req.query.merchant_id) {
    merchant = await db.queryOne('SELECT * FROM merchants WHERE id = $1 AND deleted_at IS NULL', [req.query.merchant_id]);
    if (merchant && !merchant.is_gas_synced) {
      throw new ApiError('FORBIDDEN', 'Cửa hàng này không phải do GAS quản lý', 403);
    }
  }

  let nameConflict = null;
  if (!merchant && req.query.name) {
    nameConflict = await db.queryOne(
      'SELECT id, is_gas_synced FROM merchants WHERE lower(name) = lower($1) AND deleted_at IS NULL',
      [req.query.name]
    );
  }

  if (!merchant) {
    res.json({ ok: true, data: { merchant: null, branch: null, products: [], topping_groups: [], name_conflict: nameConflict } });
    return;
  }

  // Phân loại hiện có (tên) — GAS so với STORE_CLASSIFICATION_COLUMN của sheet để hiện diff.
  const classificationRows = await db.query(
    `SELECT mc.name FROM merchant_classification_links l
       JOIN merchant_classifications mc ON mc.id = l.classification_id
      WHERE l.merchant_id = $1 ORDER BY mc.sort_order, mc.name`,
    [merchant.id]
  );
  merchant.classifications = classificationRows.map((r) => r.name);

  const branch = await db.queryOne(
    'SELECT * FROM branches WHERE merchant_id = $1 AND is_main = true AND deleted_at IS NULL',
    [merchant.id]
  );
  if (branch) {
    // Toàn bộ tuần hiện có, để GAS so diff theo từng ngày — [] = branch_hours 0 dòng = "luôn
    // mở", xem hofa-db/78_branch_operating_hours_gate.sql.
    branch.hours = await db.query(
      'SELECT weekday, open_time, close_time FROM branch_hours WHERE branch_id = $1 ORDER BY weekday',
      [branch.id]
    );
  }

  const products = await db.query(
    'SELECT * FROM products WHERE merchant_id = $1 AND deleted_at IS NULL ORDER BY created_at',
    [merchant.id]
  );
  const variantsByProduct = {};
  if (products.length) {
    const variants = await db.query(
      'SELECT * FROM product_variants WHERE product_id = ANY($1::uuid[]) ORDER BY created_at',
      [products.map((p) => p.id)]
    );
    variants.forEach((v) => { (variantsByProduct[v.product_id] ||= []).push(v); });
  }

  const groups = await db.query('SELECT * FROM topping_groups WHERE merchant_id = $1 ORDER BY created_at', [merchant.id]);
  const toppingsByGroup = {};
  const groupNameById = {};
  groups.forEach((g) => { groupNameById[g.id] = g.name; });
  if (groups.length) {
    const toppings = await db.query(
      'SELECT * FROM product_toppings WHERE group_id = ANY($1::uuid[]) ORDER BY created_at',
      [groups.map((g) => g.id)]
    );
    toppings.forEach((t) => { (toppingsByGroup[t.group_id] ||= []).push(t); });
  }

  const linksByProduct = {};
  if (products.length) {
    const links = await db.query(
      'SELECT product_id, group_id FROM product_topping_group_links WHERE product_id = ANY($1::uuid[])',
      [products.map((p) => p.id)]
    );
    links.forEach((l) => { (linksByProduct[l.product_id] ||= []).push(groupNameById[l.group_id]); });
  }

  res.json({
    ok: true,
    data: {
      merchant,
      branch,
      products: products.map((p) => ({
        ...p,
        variants: variantsByProduct[p.id] || [],
        topping_group_names: linksByProduct[p.id] || []
      })),
      topping_groups: groups.map((g) => ({ ...g, toppings: toppingsByGroup[g.id] || [] })),
      name_conflict: null
    }
  });
}));

/** Ghi toàn bộ dữ liệu 1 cửa hàng (cửa hàng + chi nhánh chính + nhóm topping/topping + sản
 * phẩm/biến thể) — không dùng transaction (nhất quán với phần còn lại của server hiện chưa
 * dùng transaction ở đâu, xem POST /merchants nhiều bước cũng không rollback), lỗi ở 1 dòng
 * không chặn các dòng còn lại — trả về id/lỗi CHO TỪNG mục để GAS ghi lại "ID hệ thống" đúng
 * chỗ và báo lỗi đúng dòng cho người dùng xử lý tiếp, giống 1 lần import hàng loạt.
 *
 * ĐỒNG BỘ ĐẦY ĐỦ (full state sync): sheet là nguồn dữ liệu DUY NHẤT cho cửa hàng do GAS quản
 * lý — mục nào có ID hệ thống (đã đồng bộ trước đó) nhưng KHÔNG còn xuất hiện trong lần gửi này
 * (bị xoá khỏi sheet) thì bị XOÁ CỨNG khỏi hệ thống luôn — biến thể/nhóm topping/topping đều
 * db.deleteById thật (không phải chỉ tắt is_active/is_open như DELETE /variants/:id của app
 * admin — công cụ GAS coi sheet là nguồn dữ liệu duy nhất nên xoá dứt điểm), riêng sản phẩm vẫn
 * xoá mềm (deleted_at + status=archived, khớp DELETE /products/:id thật — order_items đã chụp
 * sẵn tên/giá nên xoá cứng sản phẩm không cần thiết và mất luôn cả lịch sử ảnh/mô tả không lý
 * do). Nhóm topping xoá CASCADE luôn topping/liên kết con. CHỈ xoá trong phạm vi merchant đang
 * đồng bộ (đã qua requireGasMerchant/JOIN theo merchant_id ở trên) — không đụng dữ liệu cửa
 * hàng khác. */
router.post('/gas-sync/apply', asyncHandler(async (req, res) => {
  requireGasSecret(req);
  const body = req.body || {};
  if (!body.merchant || !body.merchant.name) throw new ApiError('BAD_REQUEST', 'Thiếu thông tin cửa hàng', 400);

  const result = {
    merchant: null,
    topping_groups: [],
    products: [],
    deleted: { products: [], variants: [], topping_groups: [], toppings: [] }
  };

  // ---- Cửa hàng ----
  let merchant;
  if (body.merchant.id) {
    merchant = await requireGasMerchant(body.merchant.id);
    merchant = await db.updateById('merchants', merchant.id, {
      name: body.merchant.name,
      description: body.merchant.description || null,
      logo_url: body.merchant.logo_url || null,
      cover_url: body.merchant.cover_url || null
    });
  } else {
    if (!config.gasSyncOwnerId) throw new ApiError('BAD_REQUEST', 'Server chưa cấu hình GAS_SYNC_OWNER_ID, không tạo được cửa hàng mới', 400);
    const nameTaken = await db.queryOne('SELECT id FROM merchants WHERE lower(name) = lower($1) AND deleted_at IS NULL', [body.merchant.name]);
    if (nameTaken) {
      throw new ApiError(
        'CONFLICT',
        `Đã có cửa hàng tên "${body.merchant.name}" trong hệ thống rồi (id ${nameTaken.id}) — không tự tạo trùng. Nếu đây là cùng 1 cửa hàng, dán đúng ID hệ thống vào MERCHANT trước khi đồng bộ; nếu là cửa hàng khác, đổi tên cho khác biệt.`,
        409
      );
    }
    merchant = await db.insertRow('merchants', {
      owner_id: config.gasSyncOwnerId,
      name: body.merchant.name,
      slug: await uniqueMerchantSlug(body.merchant.name),
      description: body.merchant.description || null,
      logo_url: body.merchant.logo_url || null,
      cover_url: body.merchant.cover_url || null,
      merchant_type: 'buy_on_behalf',
      status: 'active',
      is_gas_synced: true
    });
  }
  result.merchant = { id: merchant.id };

  // ---- Phân loại cửa hàng (merchant_classifications, nhiều-nhiều — full-replace theo tên,
  // cùng pattern branch_hours: xoá hết rồi insert lại đúng danh sách mới). Tên không khớp bất
  // kỳ phân loại nào đang có trong hệ thống (admin quản lý) sẽ bị bỏ qua lặng lẽ — không tự tạo
  // phân loại mới qua đường GAS. */
  const classificationNames = Array.isArray(body.merchant.classification_names) ? body.merchant.classification_names : [];
  await db.query('DELETE FROM merchant_classification_links WHERE merchant_id = $1', [merchant.id]);
  if (classificationNames.length) {
    const matched = await db.query(
      'SELECT id FROM merchant_classifications WHERE lower(name) = ANY($1::text[])',
      [classificationNames.map((n) => String(n).trim().toLowerCase())]
    );
    if (matched.length) {
      const values = matched.map((r, i) => `($1, $${i + 2})`).join(', ');
      await db.query(
        `INSERT INTO merchant_classification_links (merchant_id, classification_id) VALUES ${values}`,
        [merchant.id, ...matched.map((r) => r.id)]
      );
    }
  }

  // ---- Chi nhánh chính (branches.line1/province/latitude/longitude NOT NULL) ----
  const lat = body.merchant.latitude === '' || body.merchant.latitude == null ? null : Number(body.merchant.latitude);
  const lng = body.merchant.longitude === '' || body.merchant.longitude == null ? null : Number(body.merchant.longitude);
  if (!body.merchant.address_line1 || !body.merchant.province || lat == null || lng == null || Number.isNaN(lat) || Number.isNaN(lng)) {
    throw new ApiError('BAD_REQUEST', 'Thiếu Địa chỉ/Tỉnh thành/Vĩ độ/Kinh độ của cửa hàng — chi nhánh bắt buộc đủ 4 trường này', 400);
  }
  const branchData = {
    name: body.merchant.name,
    line1: body.merchant.address_line1,
    province: body.merchant.province,
    latitude: lat,
    longitude: lng,
    is_main: true,
    is_open: true,
    auto_accept_orders: true
  };
  const existingBranch = await db.queryOne(
    'SELECT id FROM branches WHERE merchant_id = $1 AND is_main = true AND deleted_at IS NULL',
    [merchant.id]
  );
  let branchId;
  if (existingBranch) {
    await db.updateById('branches', existingBranch.id, branchData);
    branchId = existingBranch.id;
  } else {
    const createdBranch = await db.insertRow('branches', { ...branchData, merchant_id: merchant.id });
    branchId = createdBranch.id;
  }

  // ---- Giờ hoạt động (branch_hours) — thay toàn bộ tuần bằng body.merchant.hours (danh sách
  // {weekday, open_time, close_time}, chỉ chứa NGÀY BẬT — cùng shape với PUT /branches/:id/hours
  // thật, xem hofa_store_app/lib/screens/settings/branch_hours_screen.dart). Rỗng/thiếu = xoá
  // hết = "luôn mở" theo branch_effective_status(), xem hofa-db/78_branch_operating_hours_gate.sql.
  await db.query('DELETE FROM branch_hours WHERE branch_id = $1', [branchId]);
  const hours = Array.isArray(body.merchant.hours) ? body.merchant.hours : [];
  if (hours.length) {
    await db.insertRows(
      'branch_hours',
      hours.map((h) => ({
        branch_id: branchId,
        weekday: h.weekday,
        open_time: h.open_time,
        close_time: h.close_time
      }))
    );
  }

  // ---- Nhóm topping + topping (thư viện dùng chung của cửa hàng, xem topping_groups) ----
  const groupIdByName = {};
  for (const g of (body.topping_groups || [])) {
    const item = { name: g.name, toppings: [] };
    try {
      let group;
      if (g.id) {
        const owned = await db.queryOne('SELECT id FROM topping_groups WHERE id = $1 AND merchant_id = $2', [g.id, merchant.id]);
        if (!owned) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhóm topping này ở đúng cửa hàng', 404);
        group = await db.updateById('topping_groups', g.id, {
          name: g.name, is_required: !!g.is_required, allow_multiple: !!g.allow_multiple
        });
      } else {
        const dup = await db.queryOne(
          'SELECT id FROM topping_groups WHERE merchant_id = $1 AND lower(name) = lower($2)',
          [merchant.id, g.name]
        );
        group = dup
          ? await db.updateById('topping_groups', dup.id, { is_required: !!g.is_required, allow_multiple: !!g.allow_multiple })
          : await db.insertRow('topping_groups', { merchant_id: merchant.id, name: g.name, is_required: !!g.is_required, allow_multiple: !!g.allow_multiple });
      }
      item.id = group.id;
      groupIdByName[g.name.trim().toLowerCase()] = group.id;

      for (const t of (g.toppings || [])) {
        const tItem = { name: t.name };
        try {
          let topping;
          if (t.id) {
            const owned = await db.queryOne('SELECT id FROM product_toppings WHERE id = $1 AND group_id = $2', [t.id, group.id]);
            if (!owned) throw new ApiError('NOT_FOUND', 'Không tìm thấy topping này ở đúng nhóm', 404);
            topping = await db.updateById('product_toppings', t.id, { name: t.name, price: t.price || 0, is_active: t.is_active !== false });
          } else {
            const dupT = await db.queryOne('SELECT id FROM product_toppings WHERE group_id = $1 AND lower(name) = lower($2)', [group.id, t.name]);
            topping = dupT
              ? await db.updateById('product_toppings', dupT.id, { price: t.price || 0, is_active: t.is_active !== false })
              : await db.insertRow('product_toppings', { group_id: group.id, name: t.name, price: t.price || 0, is_active: t.is_active !== false });
          }
          tItem.id = topping.id;
        } catch (err) {
          tItem.error = err.message;
        }
        item.toppings.push(tItem);
      }

      // Topping đã đồng bộ trước đó (có id thật trong nhóm này) nhưng KHÔNG còn trong lần gửi
      // này — bị xoá khỏi sheet TOPPING → xoá thật luôn (giống DELETE /toppings/:id).
      const incomingToppingIds = new Set((g.toppings || []).filter((t) => t.id).map((t) => t.id));
      const existingToppings = await db.query('SELECT id FROM product_toppings WHERE group_id = $1', [group.id]);
      for (const et of existingToppings) {
        if (!incomingToppingIds.has(et.id)) {
          await db.deleteById('product_toppings', et.id);
          result.deleted.toppings.push(et.id);
        }
      }
    } catch (err) {
      item.error = err.message;
    }
    result.topping_groups.push(item);
  }

  // Nhóm topping đã đồng bộ trước đó nhưng KHÔNG còn trong lần gửi này — bị xoá khỏi sheet
  // TOPPING → xoá thật luôn (giống DELETE /topping-groups/:id, CASCADE tự xoá topping/liên kết
  // sản phẩm con của nhóm đó).
  {
    const incomingGroupIds = new Set((body.topping_groups || []).filter((g) => g.id).map((g) => g.id));
    const existingGroups = await db.query('SELECT id FROM topping_groups WHERE merchant_id = $1', [merchant.id]);
    for (const eg of existingGroups) {
      if (!incomingGroupIds.has(eg.id)) {
        await db.deleteById('topping_groups', eg.id);
        result.deleted.topping_groups.push(eg.id);
      }
    }
  }

  // ---- Sản phẩm + biến thể ----
  for (const p of (body.products || [])) {
    const item = { name: p.name, variants: [] };
    try {
      let product;
      if (p.id) {
        const owned = await db.queryOne('SELECT id FROM products WHERE id = $1 AND merchant_id = $2', [p.id, merchant.id]);
        if (!owned) throw new ApiError('NOT_FOUND', 'Không tìm thấy sản phẩm này ở đúng cửa hàng', 404);
        product = await db.updateById('products', p.id, {
          name: p.name,
          description: p.description || null,
          unit: p.unit || 'cái',
          status: p.status || 'active',
          images: p.image_url ? [p.image_url] : []
        });
      } else {
        product = await db.insertRow('products', {
          merchant_id: merchant.id,
          name: p.name,
          slug: slugify(`${body.merchant.name}-${p.name}`),
          description: p.description || null,
          unit: p.unit || 'cái',
          status: p.status || 'active',
          sales_model: 'instant',
          images: p.image_url ? [p.image_url] : []
        });
      }
      item.id = product.id;

      const groupIds = (p.topping_group_names || [])
        .map((n) => groupIdByName[String(n).trim().toLowerCase()])
        .filter(Boolean);
      await db.query('DELETE FROM product_topping_group_links WHERE product_id = $1', [product.id]);
      if (groupIds.length) {
        await db.insertRows('product_topping_group_links', groupIds.map((gid) => ({ product_id: product.id, group_id: gid })));
      }

      for (const v of (p.variants || [])) {
        const vItem = { name: v.name };
        try {
          if (v.price === '' || v.price == null) throw new ApiError('BAD_REQUEST', 'Thiếu Giá bán', 400);
          if (v.is_default) {
            await db.query('UPDATE product_variants SET is_default = false WHERE product_id = $1', [product.id]);
          }
          let variant;
          if (v.id) {
            const owned = await db.queryOne('SELECT id FROM product_variants WHERE id = $1 AND product_id = $2', [v.id, product.id]);
            if (!owned) throw new ApiError('NOT_FOUND', 'Không tìm thấy biến thể này ở đúng sản phẩm', 404);
            variant = await db.updateById('product_variants', v.id, {
              name: v.name,
              price: v.price,
              weight_gram: v.weight_gram || null,
              is_default: !!v.is_default,
              is_active: v.is_active !== false
            });
          } else {
            variant = await db.insertRow('product_variants', {
              product_id: product.id,
              name: v.name,
              price: v.price,
              weight_gram: v.weight_gram || null,
              is_default: !!v.is_default,
              is_active: v.is_active !== false
            });
          }
          vItem.id = variant.id;
        } catch (err) {
          vItem.error = err.message;
        }
        item.variants.push(vItem);
      }

      // Biến thể đã đồng bộ trước đó (có id thật của sản phẩm này) nhưng KHÔNG còn trong lần
      // gửi này — bị xoá khỏi sheet VARIANT → xoá CỨNG luôn (khác DELETE /variants/:id thật của
      // app admin, vốn chỉ tắt is_active vì UI đó cần giữ lại để còn bật lại — công cụ GAS này
      // coi sheet là nguồn dữ liệu duy nhất nên xoá dứt điểm). An toàn vì order_items.variant_id
      // là ON DELETE SET NULL (order_items đã tự chụp sẵn product_name/variant_name/unit_price
      // lúc đặt hàng, không cần variant gốc còn tồn tại để hiển thị đơn cũ).
      const incomingVariantIds = new Set((p.variants || []).filter((v) => v.id).map((v) => v.id));
      const existingVariants = await db.query('SELECT id FROM product_variants WHERE product_id = $1', [product.id]);
      for (const ev of existingVariants) {
        if (!incomingVariantIds.has(ev.id)) {
          await db.deleteById('product_variants', ev.id);
          result.deleted.variants.push(ev.id);
        }
      }
    } catch (err) {
      item.error = err.message;
    }
    result.products.push(item);
  }

  // Sản phẩm đã đồng bộ trước đó nhưng KHÔNG còn trong lần gửi này — bị xoá khỏi sheet PRODUCT
  // → xoá mềm luôn (giống DELETE /products/:id: deleted_at + status=archived, KHÔNG đụng biến
  // thể của sản phẩm đó, đúng y hệt hành vi route thật).
  {
    const incomingProductIds = new Set((body.products || []).filter((p) => p.id).map((p) => p.id));
    const existingProducts = await db.query('SELECT id FROM products WHERE merchant_id = $1 AND deleted_at IS NULL', [merchant.id]);
    for (const ep of existingProducts) {
      if (!incomingProductIds.has(ep.id)) {
        await db.updateById('products', ep.id, { deleted_at: new Date().toISOString(), status: 'archived' });
        result.deleted.products.push(ep.id);
      }
    }
  }

  res.json({ ok: true, data: result });
}));

module.exports = router;
