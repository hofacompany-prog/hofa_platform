const { createRemoteJWKSet, jwtVerify } = require('jose');
const config = require('../config');
const db = require('../db');
const { ApiError } = require('../errors');
const asyncHandler = require('../asyncHandler');

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
 * public.users.id PHẢI trùng với auth.users.id (claims.sub) — xem README, action
 * "đăng ký/đồng bộ hồ sơ" (POST /me/sync) tạo dòng users với id = sub lúc đăng nhập lần đầu.
 *
 * Áp dụng middleware này GLOBAL: luôn parse token nếu có, không bắt buộc đăng nhập.
 * Từng route tự gọi requireAuth/requireRole (trong utils.js) để bắt buộc khi cần.
 */
const JWKS = createRemoteJWKSet(new URL(`${config.supabaseUrl}/auth/v1/.well-known/jwks.json`));

const attachContext = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];

  if (!token) {
    req.ctx = { authenticated: false, userId: null, role: null, claims: null, profile: null };
    return next();
  }

  let claims;
  try {
    const { payload } = await jwtVerify(token, JWKS);
    claims = payload;
  } catch (err) {
    throw new ApiError('UNAUTHORIZED', 'Access token không hợp lệ hoặc đã hết hạn', 401);
  }

  const profile = await db.queryOne('SELECT * FROM users WHERE id = $1', [claims.sub]);
  req.ctx = {
    authenticated: true,
    userId: claims.sub,
    claims,
    profile,
    role: profile ? profile.role : null
  };

  // Gỡ từ xa 1 thiết bị (màn "Thiết bị đăng nhập" ở admin, "Thiết bị đã đăng nhập" ở store
  // app) — server không tự quản lý session Supabase nên không thu hồi được access_token đang
  // có ngay lập tức; thay vào đó CHẶN NGAY từ request kế tiếp của đúng thiết bị đó, buộc app
  // tự đăng xuất + xoá session cục bộ khi thấy DEVICE_REVOKED (xem ApiClient._handle — hiện
  // chỉ hofa_store_app gửi header này, các app khác không có màn quản lý thiết bị nên bỏ
  // qua). Client CHỈ gửi header SAU KHI đã đăng ký thiết bị thành công ít nhất 1 lần trong
  // phiên hiện tại (DeviceSession.markRegistered) — tránh chặn nhầm ngay sau khi vừa đăng
  // nhập, lúc POST /devices đầu tiên còn chưa kịp chạy xong.
  const deviceId = req.headers['x-device-id'];
  if (deviceId) {
    const device = await db.queryOne(
      'SELECT id FROM user_devices WHERE user_id = $1 AND device_id = $2',
      [claims.sub, deviceId]
    );
    if (!device) {
      throw new ApiError('DEVICE_REVOKED', 'Thiết bị này đã bị gỡ khỏi tài khoản — vui lòng đăng nhập lại', 401);
    }
  }

  next();
});

module.exports = { attachContext };
