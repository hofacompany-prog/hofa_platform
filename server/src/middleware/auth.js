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
  next();
});

module.exports = { attachContext };
