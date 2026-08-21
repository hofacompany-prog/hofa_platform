const { createRemoteJWKSet, jwtVerify } = require('jose');
const config = require('../config');
const db = require('../db');
const { ApiError } = require('../errors');
const asyncHandler = require('../asyncHandler');
const { SCOPE_ROLES } = require('../appScope');

/**
 * Đọc header Authorization: Bearer <jwt> (Express đọc header thật, không như GAS phải
 * nhét access_token vào query/body). Xác minh chữ ký JWT bằng khoá CÔNG KHAI của Supabase
 * (JWKS — JSON Web Key Set), lấy qua {SUPABASE_URL}/auth/v1/.well-known/jwks.json.
 *
 * Trước đây verify bằng 1 secret dùng chung (HS256) — nhưng Supabase đã chuyển sang
 * "JWT Signing Keys" (ký bất đối xứng, vd ECC P-256/ES256): server ký bằng khoá riêng,
 * ai cũng verify được bằng khoá công khai tương ứng, không cần biết secret nào cả.
 * `jose` tự tải JWKS, tự cache, tự dò đúng khoá theo `kid` trong header token — kể cả khi
 * Supabase xoay khoá (standby key) sau này cũng không phải sửa code.
 *
 * Từ migration 90 (hofa-db/90_multi_role_accounts.sql): public.users.id KHÔNG còn chắc chắn
 * trùng auth.users.id nữa — 1 SĐT (1 auth.users/claims.sub) có thể có NHIỀU dòng users, mỗi
 * dòng 1 role riêng, hoàn toàn tách biệt (dữ liệu/trạng thái không liên quan nhau). Client báo
 * mình đang là app nào qua header X-App-Scope (customer/driver/merchant/admin, xem
 * ../appScope.js) — middleware chỉ tìm ĐÚNG dòng users khớp auth_user_id (claims.sub) VÀ role
 * thuộc scope đó, gán vào req.ctx.profile/userId. Không tìm thấy (chưa đăng ký role này trên
 * SĐT này) thì userId = null dù authenticated = true, giống hệt case "chưa có public.users"
 * trước đây — POST /me/sync (routes/users.js) dùng req.ctx.authUserId (= claims.sub, luôn có)
 * để tạo dòng users mới đúng role mặc định của scope.
 *
 * Áp dụng middleware này GLOBAL: luôn parse token nếu có, không bắt buộc đăng nhập.
 * Từng route tự gọi requireAuth/requireRole (trong utils.js) để bắt buộc khi cần.
 */
const JWKS = createRemoteJWKSet(new URL(`${config.supabaseUrl}/auth/v1/.well-known/jwks.json`));

const attachContext = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];

  if (!token) {
    req.ctx = { authenticated: false, userId: null, authUserId: null, appScope: null, role: null, claims: null, profile: null };
    return next();
  }

  let claims;
  try {
    const { payload } = await jwtVerify(token, JWKS);
    claims = payload;
  } catch (err) {
    throw new ApiError('UNAUTHORIZED', 'Access token không hợp lệ hoặc đã hết hạn', 401);
  }

  const appScope = req.headers['x-app-scope'];
  if (!SCOPE_ROLES[appScope]) {
    throw new ApiError('BAD_REQUEST', 'Thiếu hoặc sai định danh ứng dụng (X-App-Scope)', 400);
  }

  const profile = await db.queryOne(
    `SELECT * FROM users WHERE auth_user_id = $1 AND role = ANY($2) AND deleted_at IS NULL
      ORDER BY created_at ASC LIMIT 1`,
    [claims.sub, SCOPE_ROLES[appScope]]
  );
  req.ctx = {
    authenticated: true,
    userId: profile ? profile.id : null,
    authUserId: claims.sub,
    appScope,
    claims,
    profile,
    role: profile ? profile.role : null
  };

  // Gỡ từ xa 1 thiết bị (màn "Thiết bị đăng nhập" ở admin/store app, tab "Thiết bị admin" ở
  // admin app) — server không tự quản lý session Supabase nên không thu hồi được access_token
  // đang có ngay lập tức; thay vào đó CHẶN NGAY từ request kế tiếp của đúng thiết bị đó, buộc
  // app tự đăng xuất + xoá session cục bộ khi thấy DEVICE_REVOKED (xem ApiClient._handle —
  // cả 4 app đều gửi header này). Client CHỈ gửi header SAU KHI đã đăng ký thiết bị thành công
  // ít nhất 1 lần trong phiên hiện tại (DeviceSession.markRegistered) — tránh chặn nhầm ngay
  // sau khi vừa đăng nhập, lúc POST /devices đầu tiên còn chưa kịp chạy xong. Khoá theo
  // req.ctx.userId (hồ sơ ĐÚNG role/scope) chứ không phải claims.sub — /devices POST cũng ghi
  // theo userId này.
  const deviceId = req.headers['x-device-id'];
  if (deviceId && req.ctx.userId) {
    const device = await db.queryOne(
      'SELECT id FROM user_devices WHERE user_id = $1 AND device_id = $2',
      [req.ctx.userId, deviceId]
    );
    if (!device) {
      throw new ApiError('DEVICE_REVOKED', 'Thiết bị này đã bị gỡ khỏi tài khoản — vui lòng đăng nhập lại', 401);
    }
  }

  next();
});

module.exports = { attachContext };
