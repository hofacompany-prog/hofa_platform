/// HOFA đăng ký/đăng nhập chỉ bằng SĐT — nhưng Supabase Auth (email/password) là thứ
/// duy nhất đang cấu hình sẵn, chưa có provider OTP SMS thật. Nên tạm "giả lập" bằng
/// cách quy đổi SĐT thành 1 email nội bộ + mật khẩu cố định, KHÔNG hiện ra cho người
/// dùng thấy. Khi có OTP thật, xoá file này và toàn bộ chỗ gọi nó, thay bằng
/// supabase.auth.signInWithOtp(phone: ...).
const kTempAuthPassword = '123123';

String phoneToAuthEmail(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return '$digits@hofa.local';
}

/// Khớp CHECK constraint users_phone_format trong 01_schema.sql.
bool isValidPhone(String phone) => RegExp(r'^[0-9+]{9,20}$').hasMatch(phone);
