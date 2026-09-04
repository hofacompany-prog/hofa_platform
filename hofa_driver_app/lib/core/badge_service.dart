import 'badge_service_stub.dart' if (dart.library.html) 'badge_service_web.dart' as impl;

/// Đặt số hiện trên icon app — web (PWA đã "Thêm vào màn hình chính") dùng Badging API, còn
/// Android/iOS thật dùng app_badge_plus (xem badge_service_stub.dart) — CHÍNH XÁC theo số
/// thông báo "Đơn hàng"/chuyến giao chưa đọc, xoá ngay khi gọi (không chờ push tiếp theo).
class BadgeService {
  static Future<void> set(int count) => impl.setBadge(count);
}
