import 'pending_deep_link_stub.dart'
    if (dart.library.html) 'pending_deep_link_web.dart' as impl;

/// Cầu nối giữa firebase-messaging-sw.js (service worker) và app — xem
/// pending_deep_link_web.dart để hiểu lý do cần thêm bước này ngoài
/// clients.openWindow/client.navigate của service worker.
class PendingDeepLink {
  static Future<String?> readAndClear() => impl.readAndClearPendingDeepLink();
}
