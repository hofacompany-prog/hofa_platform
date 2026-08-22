const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { pickFields, requireFields, pagination, requireAuth, requireProfile, requireRole, requireOwnRow } = require('../utils');
const push = require('../push');
const supabaseAdmin = require('../supabaseAdmin');
const { SCOPE_DEFAULT_ROLE } = require('../appScope');

const ADDRESS_FIELDS = [
  'label', 'recipient_name', 'recipient_phone', 'line1', 'ward', 'district',
  'province', 'postal_code', 'latitude', 'longitude', 'note', 'is_default'
];

// Không lấy password_hash — endpoint admin trả cả cho web hiển thị nên phải loại field nhạy cảm.
const ADMIN_USER_COLUMNS = `
  id, phone, email, full_name, avatar_url, date_of_birth, role, status,
  phone_verified_at, email_verified_at, last_login_at, created_at, updated_at, deleted_at
`;
const ADMIN_USER_EDIT_FIELDS = ['full_name', 'email', 'phone', 'avatar_url', 'date_of_birth'];

// ---- Hồ sơ cá nhân ----

router.get('/me', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  if (!req.ctx.profile) {
    throw new ApiError('PROFILE_NOT_FOUND', 'Đã đăng nhập nhưng chưa có hồ sơ — gọi POST /me/sync trước', 404);
  }
  res.json({ ok: true, data: req.ctx.profile });
}));

/** Gọi ngay sau lần đăng nhập/đăng ký đầu tiên qua Supabase Auth để tạo hồ sơ trong public.users
 * — hoặc khi 1 SĐT đã có tài khoản Auth (role khác) nhưng CHƯA có hồ sơ cho role/app hiện tại
 * (req.ctx.userId null dù đã authenticated, xem middleware/auth.js): tạo hồ sơ MỚI, tách biệt,
 * role mặc định theo đúng scope app đang gọi (X-App-Scope), không đụng tới hồ sơ role khác. */
router.post('/me/sync', asyncHandler(async (req, res) => {
  requireAuth(req.ctx);
  requireFields(req.body, ['full_name', 'phone']);

  if (req.ctx.profile) {
    const patch = pickFields(req.body, ['full_name', 'email', 'avatar_url', 'date_of_birth']);
    const updated = Object.keys(patch).length
      ? await db.updateById('users', req.ctx.userId, patch)
      : req.ctx.profile;
    return res.json({ ok: true, data: updated });
  }

  const created = await db.insertRow('users', {
    auth_user_id: req.ctx.authUserId,
    phone: req.body.phone,
    full_name: req.body.full_name,
    email: req.body.email || null,
    role: SCOPE_DEFAULT_ROLE[req.ctx.appScope],
    status: 'active'
  });
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/me', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const data = pickFields(req.body, ['full_name', 'email', 'avatar_url', 'date_of_birth']);
  const updated = await db.updateById('users', req.ctx.userId, data);
  res.json({ ok: true, data: updated });
}));

// ---- Quản trị (admin) ----

/** Admin tạo thẳng 1 người dùng mới (kèm mật khẩu, đăng nhập được ngay) — status='active' luôn,
 * không qua bước 'pending' như tự đăng ký. role='merchant_owner' KHÔNG tạo được ở đây — chủ cửa
 * hàng luôn gắn kèm 1 merchants row, dùng POST /merchants (màn "Thêm cửa hàng") để tạo cả 2 cùng
 * lúc, tránh tạo ra hồ sơ chủ cửa hàng "mồ côi" không có cửa hàng nào. role='driver' cần đủ
 * thông tin xe/ngân hàng như POST /drivers/register (tự đăng ký) — admin nhập tay thay tài xế
 * nên coi như đã xác minh luôn (verified_at=now()), không cần duyệt lại qua
 * POST /admin/drivers/:id/verify. role='merchant_staff' cần merchant_id (chọn cửa hàng gắn vào,
 * cùng bảng merchant_staff với POST /merchants/:merchantId/staff — gộp chung vào đây cho 1 màn
 * "Tạo người dùng" duy nhất thay vì phải vào tận màn chi tiết cửa hàng). resolveOrCreateAuthIdentity
 * tái dùng chung tài khoản Auth nếu SĐT đã có hồ sơ role KHÁC (multi-role, hofa-db/90_multi_role_accounts.sql). */
router.post('/admin/users', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['full_name', 'phone', 'password', 'role']);
  const role = req.body.role;
  if (!['customer', 'merchant_staff', 'driver', 'admin'].includes(role)) {
    throw new ApiError('BAD_REQUEST', 'Vai trò không hợp lệ — chủ cửa hàng tạo qua màn "Thêm cửa hàng"', 400);
  }
  if (String(req.body.password).length < 6) {
    throw new ApiError('BAD_REQUEST', 'Mật khẩu ban đầu phải từ 6 ký tự', 400);
  }
  if (role === 'merchant_staff' && !req.body.merchant_id) {
    throw new ApiError('BAD_REQUEST', 'Cần chọn cửa hàng cho nhân viên', 400);
  }
  if (role === 'driver') {
    requireFields(req.body, [
      'national_id', 'license_no', 'vehicle_type', 'vehicle_plate',
      'bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder'
    ]);
  }

  const existingSameRole = await db.queryOne('SELECT id FROM users WHERE phone = $1 AND role = $2', [req.body.phone, role]);
  if (existingSameRole) {
    throw new ApiError('CONFLICT', 'Số điện thoại này đã có hồ sơ với vai trò này', 409);
  }

  let authUserId;
  try {
    authUserId = await supabaseAdmin.resolveOrCreateAuthIdentity(req.body.phone, req.body.password);
  } catch (err) {
    throw new ApiError('CONFLICT', `Không tạo được tài khoản mới: ${err.message}`, 409);
  }

  const user = await db.insertRow('users', {
    auth_user_id: authUserId,
    phone: req.body.phone,
    full_name: req.body.full_name,
    email: req.body.email || null,
    date_of_birth: req.body.date_of_birth || null,
    role,
    status: 'active'
  });

  if (role === 'driver') {
    await db.insertRow('drivers', {
      user_id: user.id,
      national_id: req.body.national_id,
      license_no: req.body.license_no,
      license_expiry: req.body.license_expiry || null,
      vehicle_type: req.body.vehicle_type,
      vehicle_plate: req.body.vehicle_plate,
      bank_name: req.body.bank_name,
      bank_bin: req.body.bank_bin,
      bank_account_number: req.body.bank_account_number,
      bank_account_holder: req.body.bank_account_holder,
      verified_at: new Date().toISOString()
    });
  } else if (role === 'merchant_staff') {
    await db.insertRow('merchant_staff', {
      merchant_id: req.body.merchant_id,
      user_id: user.id,
      position: req.body.position || null
    });
  }

  const full = await db.findById('users', user.id, ADMIN_USER_COLUMNS);
  res.status(201).json({ ok: true, data: full });
}));

router.get('/admin/users', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const { limit, offset } = pagination(req.query);
  const clauses = ['deleted_at IS NULL'];
  const params = [];
  if (req.query.role) { params.push(req.query.role); clauses.push(`role = $${params.length}`); }
  if (req.query.status) { params.push(req.query.status); clauses.push(`status = $${params.length}`); }
  if (req.query.q) { params.push(`%${req.query.q}%`); clauses.push(`(full_name ILIKE $${params.length} OR phone ILIKE $${params.length})`); }
  const where = `WHERE ${clauses.join(' AND ')}`;
  params.push(limit, offset);
  const rows = await db.query(
    `SELECT ${ADMIN_USER_COLUMNS} FROM users ${where} ORDER BY created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  res.json({ ok: true, data: rows });
}));

router.get('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const row = await db.findById('users', req.params.id, ADMIN_USER_COLUMNS);
  if (!row) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  const addresses = await db.query(
    'SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.params.id]
  );
  res.json({ ok: true, data: { ...row, addresses } });
}));

router.patch('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const data = pickFields(req.body, ADMIN_USER_EDIT_FIELDS);
  const updated = await db.updateById('users', req.params.id, data);
  if (!updated) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

router.patch('/admin/users/:id/status', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['status']);
  const updated = await db.updateById('users', req.params.id, { status: req.body.status });
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

router.patch('/admin/users/:id/role', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  requireFields(req.body, ['role']);
  const updated = await db.updateById('users', req.params.id, { role: req.body.role });
  const { password_hash, ...safe } = updated;
  res.json({ ok: true, data: safe });
}));

/**
 * Xoá triệt để — xoá cả tài khoản đăng nhập Supabase Auth lẫn dòng public.users, không chỉ
 * ẩn (deleted_at) như trước. Các bảng tham chiếu users.id qua ON DELETE CASCADE (địa chỉ,
 * thiết bị, đánh giá, nhân viên cửa hàng, lượt dùng voucher, thông báo...) tự dọn theo khi
 * xoá; nhưng merchants.owner_id/drivers.user_id/orders.customer_id là ON DELETE RESTRICT nên
 * Postgres sẽ chặn hẳn nếu còn — chủ động kiểm tra và báo rõ lý do trước, KHÔNG ép cascade
 * xoá luôn cửa hàng/đơn hàng, vì làm vậy sẽ phá dữ liệu của NHỮNG NGƯỜI KHÁC (khách khác đã
 * mua ở cửa hàng đó, tài xế đã giao đơn...), không chỉ của riêng người bị xoá.
 */
router.delete('/admin/users/:id', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  if (req.params.id === req.ctx.userId) {
    throw new ApiError('BAD_REQUEST', 'Không thể tự xoá tài khoản admin đang đăng nhập', 400);
  }
  const existing = await db.findById('users', req.params.id);
  if (!existing) throw new ApiError('NOT_FOUND', 'Không tìm thấy người dùng', 404);

  const [merchant, driver, orderCount] = await Promise.all([
    db.queryOne('SELECT id, name FROM merchants WHERE owner_id = $1', [req.params.id]),
    db.queryOne('SELECT id FROM drivers WHERE user_id = $1', [req.params.id]),
    db.queryOne('SELECT COUNT(*) AS count FROM orders WHERE customer_id = $1', [req.params.id])
  ]);
  const blocks = [];
  if (merchant) blocks.push(`đang đứng tên chủ cửa hàng "${merchant.name}" — xử lý cửa hàng đó trước (xoá hoặc đổi chủ)`);
  if (driver) blocks.push('có hồ sơ tài xế — xoá hồ sơ tài xế ở màn Tài xế trước');
  if (Number(orderCount.count) > 0) {
    blocks.push(
      `đã đặt ${orderCount.count} đơn hàng — xoá sẽ mất luôn dữ liệu đơn/doanh thu liên quan của cửa hàng, dùng "Tạm khoá" nếu chỉ muốn chặn đăng nhập`
    );
  }
  if (blocks.length) {
    throw new ApiError('USER_HAS_DEPENDENTS', `Không thể xoá triệt để: tài khoản ${blocks.join('; ')}.`, 409);
  }

  // 1 SĐT có thể có NHIỀU hồ sơ role dùng chung 1 tài khoản Auth (auth_user_id) — chỉ xoá thẳng
  // tài khoản Auth khi đây là hồ sơ role CUỐI CÙNG của auth_user_id đó, nếu không sẽ xoá luôn
  // đăng nhập của những role KHÁC không liên quan (vd xoá hồ sơ driver nhưng lại mất luôn tài
  // khoản customer cùng SĐT).
  const siblingCount = await db.queryOne(
    'SELECT COUNT(*) AS count FROM users WHERE auth_user_id = $1 AND id != $2',
    [existing.auth_user_id, req.params.id]
  );
  if (Number(siblingCount.count) === 0) {
    await supabaseAdmin.deleteAuthUser(existing.auth_user_id);
  }
  await db.deleteById('users', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

// ---- Địa chỉ giao hàng ----

router.get('/addresses', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const rows = await db.query(
    'SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.ctx.userId]
  );
  res.json({ ok: true, data: rows });
}));

router.post('/addresses', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['recipient_name', 'recipient_phone', 'line1', 'province']);
  const data = pickFields(req.body, ADDRESS_FIELDS);
  data.user_id = req.ctx.userId;
  // idx_addresses_one_default (01_schema.sql) chỉ cho phép ĐÚNG 1 dòng is_default=true mỗi
  // user — gỡ mặc định cũ TRƯỚC khi insert dòng mới is_default=true, tránh vi phạm unique index.
  if (data.is_default === true) {
    await db.query('UPDATE addresses SET is_default = false WHERE user_id = $1 AND is_default', [req.ctx.userId]);
  }
  const created = await db.insertRow('addresses', data);
  res.status(201).json({ ok: true, data: created });
}));

router.patch('/addresses/:id', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  await requireOwnRow('addresses', req.params.id, req.ctx.userId, 'user_id');
  const data = pickFields(req.body, ADDRESS_FIELDS);
  // Cùng lý do với POST /addresses ở trên — gỡ mặc định cũ (của DÒNG KHÁC) trước khi set dòng
  // này thành mặc định, tránh vi phạm idx_addresses_one_default.
  if (data.is_default === true) {
    await db.query('UPDATE addresses SET is_default = false WHERE user_id = $1 AND is_default AND id != $2', [req.ctx.userId, req.params.id]);
  }
  const updated = await db.updateById('addresses', req.params.id, data);
  res.json({ ok: true, data: updated });
}));

router.delete('/addresses/:id', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  await requireOwnRow('addresses', req.params.id, req.ctx.userId, 'user_id');
  await db.deleteById('addresses', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

/** Admin sửa địa chỉ CỦA NGƯỜI KHÁC (màn chi tiết người dùng, web admin) — không dùng
 * requireOwnRow (đó là để chính chủ tự sửa địa chỉ của mình, req.ctx.userId ở đây là admin chứ
 * không phải chủ địa chỉ). Chủ yếu để sửa lại toạ độ/địa chỉ chữ khi khách bấm nhầm lúc chọn
 * bản đồ hoặc địa chỉ nhập tay từ trước khi có bản đồ chọn điểm — dùng chung màn chọn bản đồ
 * LocationPickerScreen (merchants/location_picker_screen.dart) như sửa vị trí chi nhánh. */
router.patch('/admin/users/:userId/addresses/:addressId', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const address = await db.queryOne(
    'SELECT id FROM addresses WHERE id = $1 AND user_id = $2',
    [req.params.addressId, req.params.userId]
  );
  if (!address) throw new ApiError('NOT_FOUND', 'Không tìm thấy địa chỉ', 404);
  const data = pickFields(req.body, ADDRESS_FIELDS);
  // Cùng lý do với PATCH /addresses/:id — idx_addresses_one_default (01_schema.sql) chỉ cho
  // phép đúng 1 địa chỉ mặc định/user.
  if (data.is_default === true) {
    await db.query('UPDATE addresses SET is_default = false WHERE user_id = $1 AND is_default AND id != $2', [req.params.userId, req.params.addressId]);
  }
  const updated = await db.updateById('addresses', req.params.addressId, data);
  res.json({ ok: true, data: updated });
}));

// ---- Thiết bị (push notification) ----

router.get('/devices', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  const rows = await db.query('SELECT * FROM user_devices WHERE user_id = $1', [req.ctx.userId]);
  res.json({ ok: true, data: rows });
}));

router.post('/devices', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  requireFields(req.body, ['device_id']);
  const existing = await db.queryOne(
    'SELECT id FROM user_devices WHERE user_id = $1 AND device_id = $2',
    [req.ctx.userId, req.body.device_id]
  );
  const data = pickFields(req.body, ['device_id', 'device_name', 'platform', 'push_token']);
  data.last_active_at = new Date().toISOString();
  if (existing) {
    const updated = await db.updateById('user_devices', existing.id, data);
    return res.json({ ok: true, data: updated });
  }

  // Thiết bị THẬT SỰ mới với tài khoản này (chưa từng có dòng nào) — nếu tài khoản thuộc 1
  // cửa hàng (chủ hoặc nhân viên), kiểm tra giới hạn max_devices của cửa hàng đó (tính chung
  // toàn bộ chủ + nhân viên) trước khi cho thêm, tránh nhiều thiết bị cùng nhận trùng thông
  // báo đơn hàng hoặc thiết bị test cũ chiếm chỗ mãi. Khách hàng/tài xế không bị giới hạn này.
  if (['merchant_owner', 'merchant_staff'].includes(req.ctx.role)) {
    const merchant = await db.queryOne(
      `SELECT m.id, m.owner_id, m.max_devices FROM merchants m
        LEFT JOIN merchant_staff ms ON ms.merchant_id = m.id AND ms.user_id = $1
       WHERE (m.owner_id = $1 OR ms.user_id = $1) AND m.deleted_at IS NULL
       LIMIT 1`,
      [req.ctx.userId]
    );
    if (merchant) {
      const merchantUserIds = await push.resolveMerchantUserIds([merchant.id]);
      const devices = await db.query(
        `SELECT * FROM user_devices WHERE user_id = ANY($1::uuid[]) ORDER BY last_active_at ASC NULLS FIRST`,
        [merchantUserIds]
      );
      if (devices.length >= merchant.max_devices) {
        // Chỉ tự động gỡ thiết bị của CHỦ cửa hàng để nhường chỗ — nhân viên đang làm việc
        // không nên bị đăng xuất đột ngột chỉ vì chủ đăng nhập thêm máy mới (giới hạn
        // max_devices vẫn tính chung chủ + nhân viên, chỉ riêng THIẾT BỊ BỊ GỠ TỰ ĐỘNG mới
        // loại trừ nhân viên). Nếu mọi thiết bị hiện có đều của nhân viên thì không có gì tự
        // gỡ được, chủ phải tự vào màn "Thiết bị" gỡ tay 1 máy.
        const oldestOwnerDevice =
          devices.find((d) => d.user_id === merchant.owner_id) || null;
        if (req.body.force_replace_oldest === true) {
          if (!oldestOwnerDevice) {
            throw new ApiError(
              'BAD_REQUEST',
              'Không còn thiết bị nào của chủ cửa hàng để tự gỡ — vào màn Thiết bị để gỡ tay',
              400
            );
          }
          await db.deleteById('user_devices', oldestOwnerDevice.id);
        } else {
          return res.json({
            ok: true,
            data: {
              status: 'limit_reached',
              max_devices: merchant.max_devices,
              oldest_device: oldestOwnerDevice
                ? {
                    id: oldestOwnerDevice.id,
                    device_name: oldestOwnerDevice.device_name,
                    platform: oldestOwnerDevice.platform,
                    last_active_at: oldestOwnerDevice.last_active_at
                  }
                : null
            }
          });
        }
      }
    }
  }

  data.user_id = req.ctx.userId;
  const created = await db.insertRow('user_devices', data);
  res.status(201).json({ ok: true, data: { status: 'ok', ...created } });
}));

// Gỡ 1 thiết bị khỏi danh sách — không thu hồi được access_token hiện có của máy đó ngay lập
// tức (server không tự quản lý session, xác thực qua JWT/JWKS của Supabase), nhưng middleware
// attachContext chặn NGAY request kế tiếp của đúng thiết bị đó (DEVICE_REVOKED, dựa vào header
// X-Device-Id — chỉ có SAU KHI thiết bị đã đăng ký qua POST /devices ít nhất 1 lần), buộc app
// trên máy đó tự đăng xuất + xoá session Supabase cục bộ (xem ApiClient của app).
router.delete('/devices/:id', asyncHandler(async (req, res) => {
  requireProfile(req.ctx);
  await requireOwnRow('user_devices', req.params.id, req.ctx.userId, 'user_id');
  await db.deleteById('user_devices', req.params.id);
  res.json({ ok: true, data: { deleted: true } });
}));

// Admin xem/gỡ thiết bị của BẤT KỲ người dùng nào (khách, tài xế, cửa hàng...) — cùng cơ chế
// gỡ với DELETE /devices/:id ở trên (DEVICE_REVOKED chặn request kế tiếp của máy đó), chỉ khác
// không giới hạn "của chính mình" như requireOwnRow.
router.get('/admin/users/:id/devices', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const rows = await db.query(
    'SELECT * FROM user_devices WHERE user_id = $1 ORDER BY last_active_at DESC NULLS LAST',
    [req.params.id]
  );
  res.json({ ok: true, data: rows });
}));

router.delete('/admin/users/:id/devices/:deviceId', asyncHandler(async (req, res) => {
  requireRole(req.ctx, ['admin']);
  const device = await db.queryOne(
    'SELECT id FROM user_devices WHERE id = $1 AND user_id = $2',
    [req.params.deviceId, req.params.id]
  );
  if (!device) throw new ApiError('NOT_FOUND', 'Không tìm thấy thiết bị', 404);
  await db.deleteById('user_devices', req.params.deviceId);
  res.json({ ok: true, data: { deleted: true } });
}));

module.exports = router;
