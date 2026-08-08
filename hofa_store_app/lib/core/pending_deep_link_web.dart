import 'dart:js_interop';

// Định nghĩa trong web/index.html — dùng lại đúng kiểu đọc IndexedDB đã kiểm chứng ở
// web/firebase-messaging-sw.js (service worker), chạy trên window.indexedDB thay vì
// self.indexedDB (cùng API, khác ngữ cảnh thực thi).
@JS('hofaReadPendingDeepLink')
external JSPromise<JSString?> _hofaReadPendingDeepLink();

/// Đọc + xoá đường dẫn mà service worker vừa ghi lúc bấm push (xem
/// firebase-messaging-sw.js#writePendingDeepLink) — chỉ khác null khi app vừa được mở TỪ việc
/// bấm 1 thông báo lúc đã tắt hẳn/nền, bù cho việc clients.openWindow(url)/client.navigate(url)
/// không đáng tin cậy trên PWA cài kiểu WebAPK (Android có thể bỏ qua URL, luôn mở lại ở
/// start_url khai trong manifest.json — đã xác nhận qua thực tế: bấm push lúc app tắt hẳn
/// luôn rơi về trang chủ dù URL truyền cho openWindow đã đúng).
Future<String?> readAndClearPendingDeepLink() async {
  try {
    final result = await _hofaReadPendingDeepLink().toDart;
    return result?.toDart;
  } catch (_) {
    return null;
  }
}
