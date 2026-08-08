import 'pending_deep_link_stub.dart'
    if (dart.library.html) 'pending_deep_link_web.dart' as impl;

/// Cầu nối giữa firebase-messaging-sw.js (service worker) và app — xem
/// pending_deep_link_web.dart để hiểu lý do cần thêm bước này ngoài
/// clients.openWindow/client.navigate của service worker.
class PendingDeepLink {
  static Future<String?> readAndClear() => impl.readAndClearPendingDeepLink();

  /// Gọi [callback] mỗi khi service worker báo có deep link mới trong lúc app ĐANG chạy nền
  /// (chưa tắt hẳn) — xem pending_deep_link_web.dart để hiểu vì sao cần thêm kênh này ngoài
  /// readAndClear() (chỉ đọc 1 lần lúc app khởi động).
  static void onMessage(void Function() callback) => impl.setPendingDeepLinkMessageHandler(callback);
}
