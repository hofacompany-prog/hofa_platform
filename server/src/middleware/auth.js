const jwt = require('jsonwebtoken');
const config = require('../config');
const db = require('../db');
const { ApiError } = require('../errors');
const asyncHandler = require('../asyncHandler');

/**
 * Đọc header Authorization: Bearer <jwt> (Express đọc header thật, không như GAS phải
 * nhét access_token vào query/body). Xác minh chữ ký HS256 bằng JWT Secret của Supabase.
 *
 * public.users.id PHẢI trùng với auth.users.id (claims.sub) — xem README, action
 * "đăng ký/đồng bộ hồ sơ" (POST /me/sync) tạo dòng users với id = sub lúc đăng nhập lần đầu.
 *
 * Áp dụng middleware này GLOBAL: luôn parse token nếu có, không bắt buộc đăng nhập.
 * Từng route tự gọi requireAuth/requireRole (trong utils.js) để bắt buộc khi cần.
 */
const attachContext = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1];

  if (!token) {
    req.ctx = { authenticated: false, userId: null, role: null, claims: null, profile: null };
    return next();
  }

  let claims;
  try {
    claims = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
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
