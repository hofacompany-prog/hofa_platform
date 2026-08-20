const router = require('express').Router();
const db = require('../db');
const asyncHandler = require('../asyncHandler');
const { ApiError } = require('../errors');
const { requireFields } = require('../utils');
const supabaseAdmin = require('../supabaseAdmin');

const DEFAULT_RESET_PASSWORD = '123123';

/**
 * Quên mật khẩu — chưa nối SMS OTP thật (xem hofa_store_app/lib/core/phone_auth.dart) nên
 * không xác minh gì thêm ngoài đúng số điện thoại đã đăng ký, khớp mức xác thực hiện có của
 * cả hệ thống (OTP đăng ký hiện tại cũng chỉ là mã cố định 123123). Đổi thẳng mật khẩu qua
 * Supabase Admin API (Service Role key) — không cần mật khẩu cũ. new_password bỏ trống (hoặc
 * dưới 6 ký tự) thì reset về DEFAULT_RESET_PASSWORD, hiện rõ cho khách biết trước ở popup phía
 * app (xem widgets/forgot_password_dialog.dart mỗi app).
 */
router.post('/auth/forgot-password', asyncHandler(async (req, res) => {
  requireFields(req.body, ['phone']);
  const digits = String(req.body.phone).replace(/[^0-9]/g, '');
  // 1 SĐT có thể có nhiều hồ sơ role (xem hofa-db/90_multi_role_accounts.sql) nhưng đều dùng
  // chung 1 tài khoản Auth (auth_user_id) — lấy đại diện 1 dòng bất kỳ là đủ để đổi mật khẩu.
  const user = await db.queryOne(
    `SELECT auth_user_id FROM users WHERE regexp_replace(phone, '[^0-9]', '', 'g') = $1 AND deleted_at IS NULL LIMIT 1`,
    [digits]
  );
  if (!user) throw new ApiError('NOT_FOUND', 'Không tìm thấy tài khoản với số điện thoại này', 404);

  const newPassword = typeof req.body.new_password === 'string' && req.body.new_password.length >= 6
    ? req.body.new_password
    : DEFAULT_RESET_PASSWORD;
  await supabaseAdmin.updateUserPassword(user.auth_user_id, newPassword);
  res.json({ ok: true, data: { reset: true, used_default: newPassword === DEFAULT_RESET_PASSWORD } });
}));

module.exports = router;
