import 'badge_service_stub.dart' if (dart.library.html) 'badge_service_web.dart' as impl;

/// Đặt số hiện trên biểu tượng PWA ở màn hình chính (Badging API) — CHÍNH XÁC theo số thông
/// báo "Đơn hàng" chưa đọc (khác cơ chế cộng dồn tuỳ tiện trước đây trong
/// firebase-messaging-sw.js, giờ chỉ dùng cho phản hồi tức thời lúc app đang đóng, số thật
/// luôn được app tự chỉnh lại đúng mỗi khi mở lên qua hàm này). Chỉ có tác dụng trên web đã
/// "Thêm vào màn hình chính" — no-op trên mobile hoặc trình duyệt không hỗ trợ.
class BadgeService {
  static Future<void> set(int count) => impl.setBadge(count);
}
