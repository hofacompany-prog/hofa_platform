const config = require('./config');
const db = require('./db');

let client = null;
let initTried = false;

/** Client Supabase dùng Service Role key — CHỈ để gọi Admin API (auth.admin.createUser),
 * bỏ qua RLS. Lười khởi tạo giống push.js/getApp() — server vẫn phải boot được khi chưa
 * cấu hình SUPABASE_SERVICE_ROLE_KEY, chỉ luồng "admin tạo chủ cửa hàng mới" bị chặn. */
function getClient() {
  if (initTried) return client;
  initTried = true;
  if (!config.supabaseServiceRoleKey) {
    console.warn('[supabaseAdmin] SUPABASE_SERVICE_ROLE_KEY chưa cấu hình — không tạo được tài khoản chủ cửa hàng mới từ admin.');
    return null;
  }
  const { createClient } = require('@supabase/supabase-js');
  client = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });
  return client;
}

/** Email giả lập từ SĐT — PHẢI khớp đúng phoneToAuthEmail() ở phía Flutter
 * (hofa_customer_app/hofa_store_app lib/core/phone_auth.dart). Toàn hệ thống chưa nối SMS
 * OTP thật nên dùng chung mẹo này: đăng nhập lại luôn là signInWithPassword(email:
 * phoneToAuthEmail(phone), password) — tạo tài khoản ở đây phải theo đúng công thức đó,
 * nếu không chủ cửa hàng mới sẽ không đăng nhập được vào app Cửa hàng. */
function phoneToAuthEmail(phone) {
  const digits = String(phone).replace(/[^0-9]/g, '');
  return `${digits}@hofa.local`;
}

/**
 * Tạo thẳng 1 tài khoản Supabase Auth mới kèm mật khẩu (không qua OTP/xác nhận email) —
 * dùng khi admin tạo cửa hàng cho 1 chủ HOÀN TOÀN MỚI, chưa từng có tài khoản, để họ đăng
 * nhập app Cửa hàng thêm sản phẩm được ngay. Trả về auth user id — server/routes/merchants.js
 * dùng chính id này làm public.users.id (quy ước bắt buộc trùng, xem middleware/auth.js).
 * Throw nếu SUPABASE_SERVICE_ROLE_KEY chưa cấu hình hoặc email (SĐT) đã tồn tại.
 */
async function createAuthUser(phone, password) {
  const supabase = getClient();
  if (!supabase) {
    throw new Error('Server chưa cấu hình SUPABASE_SERVICE_ROLE_KEY — không tạo được tài khoản mới.');
  }
  const { data, error } = await supabase.auth.admin.createUser({
    email: phoneToAuthEmail(phone),
    password,
    email_confirm: true
  });
  if (error) throw error;
  return data.user.id;
}

/**
 * Xoá thẳng 1 tài khoản Supabase Auth — dùng khi admin xoá triệt để 1 người dùng (không chỉ
 * xoá dòng public.users), vì nếu chỉ xoá public.users mà vẫn còn tài khoản Auth thì người đó
 * đăng nhập lại là /me/sync tự tạo lại hồ sơ ngay, coi như chưa xoá được gì. Idempotent —
 * tài khoản Auth không còn tồn tại (đã xoá trước đó / lệch dữ liệu) thì coi như thành công,
 * không throw, để không chặn việc dọn dòng public.users còn sót lại.
 */
async function deleteAuthUser(authUserId) {
  const supabase = getClient();
  if (!supabase) {
    throw new Error('Server chưa cấu hình SUPABASE_SERVICE_ROLE_KEY — không xoá triệt để được tài khoản đăng nhập.');
  }
  const { error } = await supabase.auth.admin.deleteUser(authUserId);
  if (error && error.status !== 404 && !/not.*found/i.test(error.message || '')) {
    throw error;
  }
}

/**
 * Đổi thẳng mật khẩu 1 tài khoản Supabase Auth — dùng cho luồng "Quên mật khẩu" (routes/auth.js),
 * không cần biết mật khẩu cũ vì đây là Admin API (Service Role key), không phải đổi mật khẩu
 * lúc đã đăng nhập (updateUser thường của chính user đó).
 */
async function updateUserPassword(authUserId, password) {
  const supabase = getClient();
  if (!supabase) {
    throw new Error('Server chưa cấu hình SUPABASE_SERVICE_ROLE_KEY — không đổi được mật khẩu.');
  }
  const { error } = await supabase.auth.admin.updateUserById(authUserId, { password });
  if (error) throw error;
}

/**
 * Dùng khi tạo 1 hồ sơ role MỚI cho 1 SĐT (đăng ký làm nhân viên cửa hàng, admin gán chủ mới...)
 * — nếu SĐT này đã có tài khoản Auth từ trước (role khác, xem hofa-db/90_multi_role_accounts.sql)
 * thì TÁI SỬ DỤNG đúng auth_user_id đó (Supabase chỉ cho 1 SĐT/email gắn 1 auth.users, không
 * tạo trùng được — mật khẩu gửi lên trong trường hợp này bị bỏ qua vì tài khoản đã có mật khẩu
 * riêng rồi). Chỉ tạo tài khoản Auth THẬT SỰ MỚI khi SĐT này chưa từng đăng ký role nào.
 */
async function resolveOrCreateAuthIdentity(phone, password) {
  const existing = await db.queryOne('SELECT auth_user_id FROM users WHERE phone = $1 LIMIT 1', [phone]);
  if (existing) return existing.auth_user_id;
  return createAuthUser(phone, password);
}

module.exports = { createAuthUser, deleteAuthUser, updateUserPassword, phoneToAuthEmail, resolveOrCreateAuthIdentity };
