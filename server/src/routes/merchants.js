const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireRole, requireMerchantAccess, requirePermission, requireOwnerAccess, parseLatLng, haversineKmSql } = require('../utils');
const supabaseAdmin = require('../supabaseAdmin');
const push = require('../push');

const MERCHANT_FIELDS = [
  'name', 'slug', 'description', 'merchant_type', 'logo_url', 'cover_url', 'phone', 'email',
  'business_license_no', 'tax_code', 'legal_doc_urls', 'photo_urls',
  'bank_name', 'bank_bin', 'bank_account_no', 'bank_account_name',
  'commission_rate', 'min_order_amount', 'avg_prep_minutes',
  'buy_on_behalf_fee_basis', 'max_devices', 'vat_rate', 'pit_rate',
  'featured_home', 'featured_home_sort_order'
];

const BRANCH_FIELDS = [
  'name', 'phone', 'line1', 'ward', 'district', 'province',
  'latitude', 'longitude', 'is_main', 'is_open', 'delivery_radius_km', 'auto_accept_orders'
];

const FEE_TIER_FIELDS = [
  'min_threshold', 'max_threshold', 'fee_type', 'fee_fixed_amount', 'fee_percent'
];

// ---- Cửa hàng ----

/** Bán kính giao hàng mặc định toàn sàn hiện hành (hofa-db/61_delivery_radius_settings.sql) —
 * dùng làm "trần" nới rộng thêm cho chi nhánh có bán kính riêng nhỏ hơn mức này, xem
 * GET /merchants, /merchants/:id, /products (products.js). */
async function currentDefaultRadiusKm() {
  const row = await db.queryOne('SELECT default_radius_km FROM delivery_radius_settings ORDER BY updated_at DESC LIMIT 1');
  return Number(row?.default_radius_km ?? 5);
}

/** Copy bậc phí mua hộ mặc định toàn sàn (hofa-db/87_platform_buy_on_behalf_fee_defaults.sql,
 * admin cấu hình ở web admin) sang merchants.buy_on_behalf_fee_basis + merchant_fee_tiers cho
 * 1 cửa hàng buy_on_behalf VỪA TẠO — chỉ chạy đúng 1 lần lúc tạo mới, không đụng cửa hàng đã
 * có sẵn tiers riêng. Best-effort: nuốt lỗi nếu 2 bảng platform_buy_on_behalf_fee_* chưa tồn
 * tại (migration 87 chưa chạy) hoặc admin chưa cấu hình bậc nào — cửa hàng vẫn tạo được bình
 * thường, chỉ là chưa có phí mua hộ mặc định (giống hành vi trước khi có tính năng này). */
async function applyPlatformFeeDefaults(merchantId) {
  try {
    const settings = await db.queryOne(
      'SELECT fee_basis FROM platform_buy_on_behalf_fee_settings ORDER BY updated_at DESC LIMIT 1'
    );
    const tiers = await db.query(
      'SELECT min_threshold, max_threshold, fee_type, fee_fixed_amount, fee_percent FROM platform_buy_on_behalf_fee_tiers ORDER BY min_threshold ASC'
    );
    if (!settings || !tiers.length) return;
    await db.updateById('merchants', merchantId, { buy_on_behalf_fee_basis: settings.fee_basis });
    for (const t of tiers) {
      // eslint-disable-next-line no-await-in-loop
      await db.insertRow('merchant_fee_tiers', { merchant_id: merchantId, ...t });
    }
  } catch (err) {
    console.error('Không copy được phí mua hộ mặc định toàn sàn cho cửa hàng', merchantId, err);
  }
}

router.get('/merchants', asyncHandler(async (req, res) => {
  const { limit, offset } = pagination(req.query);
  const clauses = ['deleted_at IS NULL'];
  const params = [];

  const isPrivileged = req.ctx.authenticated && req.ctx.role === 'admin';
  if (!isPrivileged) clauses.push(`status = 'active'`);
  if (req.query.merchant_type) { params.push(req.query.merchant_type); clauses.push(`merchant_type = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`name ILIKE $${params.length}`); }
  // Danh sách duyệt mặc định của trang chủ app Khách CHỈ hiện cửa hàng admin đã chọn
  // (featured_home) — cửa hàng khác vẫn tồn tại bình thường, tìm được qua ô tìm kiếm (có q) nên
  // bỏ qua bộ lọc này khi có q. Admin xem danh sách quản lý (GET /merchants không phải để duyệt
  // mua hàng) thì thấy đủ mọi cửa hàng như trước, không bị lọc — xem
  // hofa-db/80_product_sort_and_featured_home.sql.
  const filterFeaturedHome = !isPrivileged && !req.query.q;
  if (filterFeaturedHome) clauses.push(`m.featured_home = true`);
  // Lọc theo phân loại cửa hàng (Nhà hàng/Cà phê/...) — chọn nhiều id cách nhau bằng dấu phẩy,
  // khớp NẾU CÓ ÍT NHẤT 1 phân loại trùng (OR), xem hofa-db/71_merchant_classifications.sql.
  if (req.query.classification_ids) {
    const ids = String(req.query.classification_ids).split(',').filter(Boolean);
    if (ids.length) {
      params.push(ids);
      clauses.push(
        `EXISTS (SELECT 1 FROM merchant_classification_links l WHERE l.merchant_id = m.id AND l.classification_id = ANY($${params.length}::uuid[]))`
      );
    }
  }

  // Khoảng cách từ chi nhánh gần nhất (ưu tiên chi nhánh đang mở) tới toạ độ khách đang xem —
  // chỉ tính khi client gửi kèm lat/lng (địa chỉ mặc định của khách, xem
  // merchant_repository.dart phía app khách), bỏ qua (null) nếu khách chưa lưu địa chỉ nào.
  // Đồng thời ẩn hẳn cửa hàng nếu vượt CẢ bán kính riêng của chi nhánh gần nhất LẪN bán kính
  // mặc định toàn sàn (delivery_radius_settings) — còn vượt riêng bán kính chi nhánh nhưng vẫn
  // trong mức mặc định thì vẫn hiện, kèm cờ beyond_own_radius để app khách tô cam khoảng cách
  // (xem hofa-db/61_delivery_radius_settings.sql).
  let distanceSelect = 'NULL::numeric AS distance_km, false AS beyond_own_radius';
  let distanceJoin = '';
  const coords = parseLatLng(req.query);
  if (coords) {
    params.push(coords.lat, coords.lng);
    const latParam = params.length - 1;
    const lngParam = params.length;
    const defaultRadiusKm = await currentDefaultRadiusKm();
    params.push(defaultRadiusKm);
    const defaultRadiusParam = params.length;
    distanceSelect = 'nearest_branch.distance_km, COALESCE(nearest_branch.distance_km > nearest_branch.delivery_radius_km, false) AS beyond_own_radius';
    distanceJoin = `
      LEFT JOIN LATERAL (
        SELECT (${haversineKmSql(latParam, lngParam)}) AS distance_km, b.delivery_radius_km
          FROM branches b
         WHERE b.merchant_id = m.id AND b.deleted_at IS NULL
           AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL
         ORDER BY b.is_open DESC, distance_km ASC
         LIMIT 1
      ) nearest_branch ON true`;
    clauses.push(`(nearest_branch.distance_km IS NULL OR nearest_branch.distance_km <= GREATEST(nearest_branch.delivery_radius_km, $${defaultRadiusParam}))`);
  }

  // Sắp xếp "Gần tôi" (sort=distance) — chỉ áp dụng được khi có toạ độ khách, ngược lại rơi về
  // mặc định (đánh giá cao trước) như cũ, không báo lỗi (khách chưa lưu địa chỉ vẫn dùng được
  // trang chủ bình thường). Cửa hàng chưa có chi nhánh nào định vị được (distance_km NULL) xếp
  // xuống cuối thay vì lên đầu (Postgres mặc định NULL lớn nhất khi ASC). Đang lọc theo
  // featured_home thì luôn ưu tiên đúng thứ tự admin đã sắp (featured_home_sort_order) trước
  // mọi cách sắp khác.
  const featuredOrderPrefix = filterFeaturedHome
    ? 'm.featured_home_sort_order ASC, '
    : '';
  const orderBy = req.query.sort === 'distance' && coords
    ? `${featuredOrderPrefix}nearest_branch.distance_km ASC NULLS LAST, m.rating_avg DESC, m.id DESC`
    : `${featuredOrderPrefix}m.rating_avg DESC, m.created_at DESC, m.id DESC`;

  params.push(limit, offset);
  const rows = await db.query(
    `SELECT m.*,
            EXISTS (
              SELECT 1 FROM branches b
               WHERE b.merchant_id = m.id AND b.deleted_at IS NULL AND branch_effective_status(b.id) = 'open'
            ) AS has_open_branch,
            COALESCE((
              SELECT CASE
                       WHEN bool_or(branch_effective_status(b.id) = 'open') THEN 'open'
                       WHEN bool_or(branch_effective_status(b.id) = 'on_break') THEN 'on_break'
                       WHEN COUNT(*) > 0 THEN 'closed_hours'
                     END
                FROM branches b WHERE b.merchant_id = m.id AND b.deleted_at IS NULL
            ), 'open') AS display_status,
            COALESCE((
              SELECT jsonb_agg(jsonb_build_object('id', mc.id, 'name', mc.name) ORDER BY mc.sort_order, mc.name)
                FROM merchant_classification_links l
                JOIN merchant_classifications mc ON mc.id = l.classification_id
               WHERE l.merchant_id = m.id
            ), '[]'::jsonb) AS classifications,
            ${distanceSelect}
       FROM merchants m
       ${distanceJoin}
      WHERE ${clauses.join(' AND ')}
      ORDER BY ${orderBy}
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows, hasMore: rows.length === limit });
}));

/** Cửa hàng của chính user hiện tại — bất kể trạng thái (draft/pending_review/active...),
 * khác với GET /merchants (chỉ trả active cho người ngoài). Phải đặt TRƯỚC route /merchants/:id
 * để Express không hiểu nhầm "mine" là 1 giá trị :id. */
router.get('/merchants/mine', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  const owned = await db.query(
    'SELECT * FROM merchants WHERE owner_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC',
    [req.ctx.userId]
  );
  if (owned.length) {
    // Chủ cửa hàng luôn full quyền — my_permissions null nghĩa là "không giới hạn", phân biệt
    // với nhân viên luôn có 1 mảng permissions cụ thể (có thể rỗng).
    return res.json({ ok: true, data: owned.map((m) => ({ ...m, my_permissions: null })) });
  }
  // Không sở hữu cửa hàng nào — có thể là nhân viên (merchant_staff) của 1 cửa hàng khác.
  const staffRows = await db.query(
    `SELECT m.*, ms.permissions AS my_permissions
       FROM merchant_staff ms
       JOIN merchants m ON m.id = ms.merchant_id
      WHERE ms.user_id = $1 AND m.deleted_at IS NULL
      ORDER BY ms.created_at DESC`,
    [req.ctx.userId]
  );
  res.json({ ok: true, data: staffRows });
}));

// Field nhạy cảm (ngân hàng/thuế) — chỉ admin hoặc chính chủ cửa hàng mới thấy.
const SENSITIVE_MERCHANT_FIELDS = [
  'bank_name', 'bank_bin', 'bank_account_no', 'bank_account_name', 'tax_code', 'business_license_no', 'legal_doc_urls'
];

router.get('/merchants/:id', asyncHandler(async (req, res) => {
  const row = await db.queryOne('SELECT * FROM merchants WHERE id = $1 AND deleted_at IS NULL', [req.params.id]);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);

  row.classifications = await db.query(
    `SELECT mc.id, mc.name FROM merchant_classification_links l
       JOIN merchant_classifications mc ON mc.id = l.classification_id
      WHERE l.merchant_id = $1
      ORDER BY mc.sort_order, mc.name`,
    [req.params.id]
  );

  // Cùng cách tính với GET /merchants (danh sách) — xem haversineKmSql. Khác GET /merchants:
  // KHÔNG ẩn/404 dù vượt cả 2 mức bán kính — khách có thể vào thẳng trang này từ mục yêu thích/
  // lịch sử đơn dù nay đã ngoài phạm vi, chỉ cần cờ beyond_own_radius để tô cam khoảng cách.
  const coords = parseLatLng(req.query);
  if (coords) {
    const nearest = await db.queryOne(
      `SELECT (${haversineKmSql(1, 2)}) AS distance_km, b.delivery_radius_km
         FROM branches b
        WHERE b.merchant_id = $3 AND b.deleted_at IS NULL
          AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL
        ORDER BY b.is_open DESC, distance_km ASC
        LIMIT 1`,
      [coords.lat, coords.lng, req.params.id]
    );
    row.distance_km = nearest?.distance_km ?? null;
    row.beyond_own_radius = nearest ? nearest.distance_km > nearest.delivery_radius_km : false;
  }

  const isPrivileged = req.ctx.authenticated && (req.ctx.role === 'admin' || row.owner_id === req.ctx.userId);
  if (!isPrivileged) {
    SENSITIVE_MERCHANT_FIELDS.forEach((f) => delete row[f]);
    // Khách vẫn xem được sản phẩm của cửa hàng đang tạm đóng (chỉ không đặt hàng được, xem
    // POST /orders) — nên app khách cần biết trạng thái này để tự xám giao diện/khoá nút đặt,
    // không lộ branches thật (địa chỉ/SĐT từng chi nhánh không cần thiết cho khách) — RIÊNG toạ
    // độ chi nhánh chính (is_main) vẫn lộ ra để màn chi tiết cửa hàng có nút "Xem vị trí quán"
    // mở Google Maps (xem hofa_customer_app merchant_detail_screen.dart), không kèm địa chỉ chữ/
    // SĐT vì 2 thứ đó vẫn không cần thiết cho khách.
    const status = await db.queryOne(
      `SELECT
         EXISTS (
           SELECT 1 FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL AND branch_effective_status(b.id) = 'open'
         ) AS has_open_branch,
         COALESCE((
           SELECT CASE
                    WHEN bool_or(branch_effective_status(b.id) = 'open') THEN 'open'
                    WHEN bool_or(branch_effective_status(b.id) = 'on_break') THEN 'on_break'
                    WHEN COUNT(*) > 0 THEN 'closed_hours'
                  END
             FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL
         ), 'open') AS display_status,
         (
           SELECT b.latitude FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL
             AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL
            ORDER BY is_main DESC LIMIT 1
         ) AS branch_latitude,
         (
           SELECT b.longitude FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL
             AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL
            ORDER BY is_main DESC LIMIT 1
         ) AS branch_longitude`,
      [req.params.id]
    );
    return res.json({
      ok: true,
      data: {
        ...row,
        has_open_branch: status.has_open_branch,
        display_status: status.display_status,
        branch_latitude: status.branch_latitude,
        branch_longitude: status.branch_longitude
      }
    });
  }

  const [owner, branches] = await Promise.all([
    db.queryOne('SELECT id, full_name, phone, email FROM users WHERE id = $1', [row.owner_id]),
    db.query(
      `SELECT b.*, branch_effective_status(b.id) AS status
         FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL ORDER BY is_main DESC`,
      [req.params.id]
    )
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
  if (merchant.merchant_type === 'buy_on_behalf') await applyPlatformFeeDefaults(merchant.id);
  res.status(201).json({ ok: true, data: merchant });
}));

router.patch('/merchants/:id', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.id);
  const data = pickFields(req.body, MERCHANT_FIELDS);

  // Admin gắn/tạo tài khoản chủ cửa hàng thật — dùng lúc chuyển cửa hàng mua hộ (owner_id đang
  // trỏ vào 1 tài khoản dùng chung GAS_SYNC_OWNER_ID, xem gasSync.js) sang cửa hàng thường có
  // chủ thật, để chủ tự đăng nhập app Cửa hàng bằng SĐT nhận thông báo đơn hàng. CÙNG pattern
  // với owner_phone/owner_password ở POST /merchants — chỉ khác là ở đây chạy trong PATCH nên
  // giới hạn admin (owner/staff PATCH cửa hàng của chính mình không được đổi chủ).
  if (req.ctx.role === 'admin' && req.body.owner_phone) {
    let ownerId;
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
    data.owner_id = ownerId;
    // Đã có chủ thật tự quản lý — không còn để GAS đồng bộ/tự dọn "mồ côi" vào cửa hàng này nữa
    // (xem is_gas_synced ở hofa-db/85_merchant_gas_sync.sql, requireGasMerchant ở gasSync.js).
    data.is_gas_synced = false;
    await db.query(`UPDATE users SET role = 'merchant_owner' WHERE id = $1 AND role = 'customer'`, [ownerId]);
  }

  const updated = await db.updateById('merchants', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

// Ghi đè toàn bộ phân loại cửa hàng — xoá hết rồi insert lại đúng danh sách mới, cùng pattern
// PUT /branches/:id/hours, xem hofa-db/71_merchant_classifications.sql.
router.put('/merchants/:id/classifications', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.id);
  requireFields(req.body, ['classification_ids']);
  await db.query('DELETE FROM merchant_classification_links WHERE merchant_id = $1', [req.params.id]);
  const ids = Array.isArray(req.body.classification_ids) ? req.body.classification_ids : [];
  if (ids.length) {
    const values = ids.map((_, i) => `($1, $${i + 2})`).join(', ');
    await db.query(
      `INSERT INTO merchant_classification_links (merchant_id, classification_id) VALUES ${values}`,
      [req.params.id, ...ids]
    );
  }
  const rows = await db.query(
    `SELECT mc.id, mc.name FROM merchant_classification_links l
       JOIN merchant_classifications mc ON mc.id = l.classification_id
      WHERE l.merchant_id = $1
      ORDER BY mc.sort_order, mc.name`,
    [req.params.id]
  );
  res.json({ ok: true, data: rows });
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

/** Xoá THẬT — DELETE hẳn khỏi Postgres, không phải xoá mềm nữa (quyết định có chủ đích, xem
 * hofa-db/52_merchant_hard_delete.sql). CASCADE kéo theo mất VĨNH VIỄN: branches, products,
 * orders (+ order_items/lịch sử trạng thái/reviews/voucher_redemptions của các đơn đó),
 * payments, stock_movements, merchant_staff, merchant_categories, topping_groups — không thể
 * khôi phục. Chỉ admin, không guard bằng deleted_at nữa vì cột đó không còn ý nghĩa với route
 * này (chỉ còn dùng lọc danh sách các cửa hàng đã xoá TRƯỚC migration 52, nếu còn sót). */
router.delete('/merchants/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const deleted = await db.deleteById('merchants', req.params.id);
  if (!deleted) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);
  res.json({ ok: true, data: deleted });
}));

/** Số liệu nhanh cho màn Trang chủ store app — đơn đang chuẩn bị (không tính riêng theo
 * ngày, cửa hàng cần biết đang có bao nhiêu đơn tồn đọng; gồm cả 'confirmed' lẫn 'preparing' —
 * khớp đúng nhóm "Đang chuẩn bị" ở màn danh sách đơn hàng, orders_list_screen.dart, và cũng là
 * số hiện ở badge icon "Đơn hàng" trên Trang chủ + thanh điều hướng chính, store app) và thu
 * nhập/số đơn HÔM NAY theo giờ Việt Nam (không dùng giờ server, tránh lệch múi giờ làm sai mốc
 * "hôm nay"). Thu nhập loại trừ đơn đã huỷ/hoàn tiền, số đơn "hôm nay" thì tính luôn cả đơn huỷ
 * để đúng số đơn thực nhận trong ngày (khớp cảm nhận thông thường của cửa hàng: "hôm nay có bao
 * nhiêu đơn").
 */
router.get('/merchants/:merchantId/stats/today', asyncHandler(async (req, res) => {
  await requireMerchantAccess(req.ctx, req.params.merchantId);
  const [preparing, today] = await Promise.all([
    db.queryOne(
      `SELECT COUNT(*)::int AS count FROM orders WHERE merchant_id = $1 AND status IN ('confirmed', 'preparing')`,
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

/**
 * "Tài chính" (store app, tab Tóm tắt) — doanh thu, hoa hồng, thuế GTGT/TNCN (áp thẳng lên
 * doanh thu gộp, không lồng thuế trong thuế — đúng cách Thông tư 40/2021 tính thuế khoán) và
 * thu nhập ròng cho 1 khoảng thời gian. period=today|yesterday|week|custom, custom cần kèm
 * from/to (YYYY-MM-DD). Mọi mốc ngày tính theo giờ Việt Nam, không dùng giờ server.
 *
 * CHỈ tính đơn đã ở trạng thái 'delivered' — đọc từ sổ cái merchant_wallet_transactions
 * (entry_type=order_payout, chỉ được insert lúc đơn chuyển sang delivered, xem
 * update_order_status trong hofa-db/64_merchant_wallet_ledger.sql), không tính đơn đang chạy
 * dù đã đặt/đang chuẩn bị — khác hẳn cách tính cũ (mọi đơn chưa huỷ, tính ngay từ lúc đặt).
 * revenue/commission_amount/vat_amount/pit_amount lấy lại đúng số đã CHỐT trên từng đơn
 * (orders.subtotal/commission_amount/vat_amount/pit_amount, xem
 * hofa-db/67_merchant_net_income_wallet.sql) thay vì suy từ tỷ lệ hiện tại của cửa hàng —
 * chính xác hơn nếu tỷ lệ từng đổi giữa chừng, và net_income ở đây LUÔN khớp đúng số thực đã
 * cộng vào merchant_wallet_transactions (merchant_payout = subtotal - commission_amount -
 * vat_amount - pit_amount), không còn lệch với số dư ví ở tab "Số tiền thu về".
 */
router.get('/merchants/:merchantId/finance/summary', asyncHandler(async (req, res) => {
  await requirePermission(req.ctx, req.params.merchantId, 'finance.view');
  const merchant = await db.queryOne(
    'SELECT commission_rate, vat_rate, pit_rate FROM merchants WHERE id = $1',
    [req.params.merchantId]
  );
  if (!merchant) throw new ApiError('NOT_FOUND', 'Không tìm thấy cửa hàng', 404);

  const period = req.query.period || 'today';
  if (period === 'custom') requireFields(req.query, ['from', 'to']);

  const row = await db.queryOne(
    `WITH bounds AS (
       SELECT
         CASE $2
           WHEN 'yesterday' THEN (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date - 1
           WHEN 'week' THEN date_trunc('week', (now() AT TIME ZONE 'Asia/Ho_Chi_Minh'))::date
           WHEN 'custom' THEN $3::date
           ELSE (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
         END AS from_date,
         CASE $2
           WHEN 'yesterday' THEN (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date - 1
           WHEN 'custom' THEN $4::date
           ELSE (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
         END AS to_date
     )
     SELECT b.from_date, b.to_date,
            COALESCE(SUM(o.subtotal), 0)::bigint AS revenue,
            COALESCE(SUM(o.commission_amount), 0)::bigint AS commission_amount,
            COALESCE(SUM(o.vat_amount), 0)::bigint AS vat_amount,
            COALESCE(SUM(o.pit_amount), 0)::bigint AS pit_amount,
            COUNT(o.id)::int AS order_count
       FROM bounds b
       LEFT JOIN merchant_wallet_transactions t ON t.merchant_id = $1 AND t.entry_type = 'order_payout'
         AND (t.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date BETWEEN b.from_date AND b.to_date
       LEFT JOIN orders o ON o.id = t.order_id
      GROUP BY b.from_date, b.to_date`,
    [req.params.merchantId, period, req.query.from || null, req.query.to || null]
  );

  const revenue = Number(row.revenue);
  const commissionAmount = Number(row.commission_amount);
  const vatAmount = Number(row.vat_amount);
  const pitAmount = Number(row.pit_amount);
  // = SUM(merchant_payout) của các đơn trong khoảng này — đúng bằng số đã cộng vào sổ cái.
  const netIncome = revenue - commissionAmount - vatAmount - pitAmount;

  res.json({
    ok: true,
    data: {
      period,
      from: row.from_date,
      to: row.to_date,
      order_count: row.order_count,
      revenue,
      commission_rate: Number(merchant.commission_rate),
      commission_amount: commissionAmount,
      vat_rate: Number(merchant.vat_rate),
      vat_amount: vatAmount,
      pit_rate: Number(merchant.pit_rate),
      pit_amount: pitAmount,
      net_income: netIncome
    }
  });
}));

// ---- Chi nhánh ----

router.get('/merchants/:merchantId/branches', asyncHandler(async (req, res) => {
  const rows = await db.query(
    `SELECT b.*, branch_effective_status(b.id) AS status
       FROM branches b WHERE b.merchant_id = $1 AND b.deleted_at IS NULL ORDER BY is_main DESC`,
    [req.params.merchantId]
  );
  res.json({ ok: true, data: rows });
}));

/** Kèm m.name AS merchant_name — app tài xế cần tên quán (khác tên chi nhánh) để hiện ở màn
 * nhận đơn/chi tiết/bản đồ chuyến giao. Kèm m.merchant_type để app tài xế biết đơn mua hộ
 * (buy_on_behalf) — không có OTP ở bước lấy hàng, hiện danh sách cần mua thay vào đó. */
router.get('/branches/:id', asyncHandler(async (req, res) => {
  const row = await db.queryOne(
    `SELECT b.*, m.name AS merchant_name, m.merchant_type, branch_effective_status(b.id) AS status
       FROM branches b
       JOIN merchants m ON m.id = b.merchant_id
      WHERE b.id = $1 AND b.deleted_at IS NULL`,
    [req.params.id]
  );
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

/** Công tắc "Tạm nghỉ": tắt kèm break_until (hẹn giờ tự mở lại, null = vô thời hạn — tắt tay
 * không hẹn giờ, hoặc hệ thống tự tắt do cửa hàng không xác nhận đơn kịp, xem
 * order_detail_screen.dart _cancelDueToTimeout ở app Cửa hàng). Bật lại luôn xoá break_until,
 * dù đang mở tay sớm hay hết hạn tự nhiên — xem hofa-db/78_branch_operating_hours_gate.sql. */
router.patch('/branches/:id/toggle-open', asyncHandler(async (req, res) => {
  requireFields(req.body, ['is_open']);
  const branch = await db.queryOne('SELECT id, merchant_id FROM branches WHERE id = $1', [req.params.id]);
  if (!branch) throw new ApiError('NOT_FOUND', 'Không tìm thấy chi nhánh', 404);
  await requireMerchantAccess(req.ctx, branch.merchant_id);
  const isOpen = !!req.body.is_open;
  const updated = await db.updateById('branches', req.params.id, {
    is_open: isOpen,
    break_until: isOpen ? null : (req.body.break_until || null)
  });
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
// Chỉ CHỦ cửa hàng (không phải merchant_staff dù có quyền gì) mới thêm/sửa/xoá được nhân
// viên — xem requireOwnerAccess. Tạo nhân viên = tạo thẳng 1 tài khoản Supabase Auth mới
// bằng SĐT + mật khẩu chủ tự đặt (tái dùng đúng pattern supabaseAdmin.createAuthUser đã
// dùng khi admin tạo chủ cửa hàng mới, xem POST /merchants phía trên) — nhân viên đăng nhập
// được ngay, không cần tự đăng ký OTP trước.

const STAFF_PERMISSIONS = [
  'products.view', 'products.manage',
  'orders.view', 'orders.manage',
  'inventory.manage',
  'finance.view',
];
// staff.manage CỐ Ý không nằm trong danh sách này — quản lý nhân viên luôn chỉ dành cho chủ
// cửa hàng ở bản đầu, không cấp được qua UI/API này dù có truyền lên.

function sanitizeStaffPermissions(input) {
  return Array.isArray(input) ? input.filter((p) => STAFF_PERMISSIONS.includes(p)) : [];
}

const STAFF_SELECT = `
  SELECT ms.id, ms.merchant_id, ms.branch_id, ms.user_id, ms.position, ms.permissions, ms.created_at,
         u.full_name, u.phone
    FROM merchant_staff ms
    JOIN users u ON u.id = ms.user_id
`;

router.get('/merchants/:merchantId/staff', asyncHandler(async (req, res) => {
  await requireOwnerAccess(req.ctx, req.params.merchantId);
  const rows = await db.query(
    `${STAFF_SELECT} WHERE ms.merchant_id = $1 ORDER BY ms.created_at ASC`,
    [req.params.merchantId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/merchants/:merchantId/staff', asyncHandler(async (req, res) => {
  requireFields(req.body, ['full_name', 'phone', 'password']);
  await requireOwnerAccess(req.ctx, req.params.merchantId);

  const existing = await db.queryOne('SELECT id FROM users WHERE phone = $1', [req.body.phone]);
  if (existing) {
    throw new ApiError(
      'CONFLICT',
      'Số điện thoại này đã có tài khoản HOFA — không thể tạo tài khoản nhân viên mới với SĐT này',
      409
    );
  }
  if (String(req.body.password).length < 6) {
    throw new ApiError('BAD_REQUEST', 'Mật khẩu ban đầu phải từ 6 ký tự', 400);
  }

  let authUserId;
  try {
    authUserId = await supabaseAdmin.createAuthUser(req.body.phone, req.body.password);
  } catch (err) {
    throw new ApiError('CONFLICT', `Không tạo được tài khoản mới: ${err.message}`, 409);
  }
  const user = await db.insertRow('users', {
    id: authUserId,
    phone: req.body.phone,
    full_name: req.body.full_name,
    role: 'merchant_staff',
    status: 'active'
  });
  const created = await db.insertRow('merchant_staff', {
    merchant_id: req.params.merchantId,
    branch_id: req.body.branch_id || null,
    user_id: user.id,
    position: req.body.position || null,
    permissions: sanitizeStaffPermissions(req.body.permissions)
  });
  const [full] = await db.query(`${STAFF_SELECT} WHERE ms.id = $1`, [created.id]);
  res.status(201).json({ ok: true, data: full });
}));

router.patch('/merchants/:merchantId/staff/:id', asyncHandler(async (req, res) => {
  await requireOwnerAccess(req.ctx, req.params.merchantId);
  const data = {};
  if (req.body.position !== undefined) data.position = req.body.position;
  if (req.body.permissions !== undefined) data.permissions = sanitizeStaffPermissions(req.body.permissions);
  if (Object.keys(data).length) await db.updateById('merchant_staff', req.params.id, data);
  const [full] = await db.query(`${STAFF_SELECT} WHERE ms.id = $1`, [req.params.id]);
  if (!full) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhân viên', 404);
  res.json({ ok: true, data: full });
}));

/** Gỡ khỏi cửa hàng — không xoá tài khoản Supabase Auth (họ vẫn còn tài khoản HOFA bình
 * thường). Hạ role về lại 'customer' nếu không còn thuộc merchant_staff nào khác, tránh role
 * 'merchant_staff' mồ côi không gắn cửa hàng nào. */
router.delete('/merchants/:merchantId/staff/:id', asyncHandler(async (req, res) => {
  await requireOwnerAccess(req.ctx, req.params.merchantId);
  const staff = await db.queryOne('SELECT user_id FROM merchant_staff WHERE id = $1', [req.params.id]);
  if (!staff) throw new ApiError('NOT_FOUND', 'Không tìm thấy nhân viên', 404);
  await db.deleteById('merchant_staff', req.params.id);
  const remaining = await db.queryOne('SELECT id FROM merchant_staff WHERE user_id = $1', [staff.user_id]);
  if (!remaining) {
    await db.query(`UPDATE users SET role = 'customer' WHERE id = $1 AND role = 'merchant_staff'`, [staff.user_id]);
  }
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
