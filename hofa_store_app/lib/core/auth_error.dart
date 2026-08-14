import 'package:supabase_flutter/supabase_flutter.dart';

/// Dịch các thông báo lỗi tiếng Anh THƯỜNG GẶP của Supabase Auth sang tiếng Việt — lỗi lạ/chưa
/// gặp giữ nguyên message gốc (không nuốt mất thông tin, vẫn debug được).
String translateAuthError(AuthException e) {
  final m = e.message;
  if (m.contains('Invalid login credentials')) {
    return 'Số điện thoại hoặc mật khẩu không đúng';
  }
  if (m.contains('User already registered') ||
      m.contains('already registered')) {
    return 'Số điện thoại này đã có tài khoản';
  }
  if (m.contains('Phone not confirmed') || m.contains('Email not confirmed')) {
    return 'Tài khoản chưa xác thực — vui lòng xác thực OTP trước';
  }
  if (m.contains('Token has expired') ||
      m.contains('Invalid token') ||
      m.contains('otp_expired')) {
    return 'Mã xác thực đã hết hạn hoặc không đúng, thử lại';
  }
  if (m.contains('rate limit') ||
      m.contains('Too many requests') ||
      m.contains('For security purposes')) {
    return 'Bạn thao tác quá nhanh — vui lòng đợi ít phút rồi thử lại';
  }
  if (m.contains('Password should be at least')) {
    return 'Mật khẩu phải từ 6 ký tự';
  }
  if (m.contains('should be different from the old password')) {
    return 'Mật khẩu mới phải khác mật khẩu cũ';
  }
  if (m.contains('Unable to validate email address')) {
    return 'Số điện thoại không đúng định dạng';
  }
  if (m.contains('Network') || m.contains('SocketException')) {
    return 'Lỗi kết nối mạng — kiểm tra internet rồi thử lại';
  }
  return m;
}
