import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

extension on JSObject {
  external JSPromise<JSAny?> setAppBadge(int contents);
  external JSPromise<JSAny?> clearAppBadge();
}

/// setAppBadge/clearAppBadge chưa có binding sẵn trong dart:html — khai báo trực tiếp qua
/// dart:js_interop, tự kiểm tra property có tồn tại không trước khi gọi (Safari/Firefox
/// desktop chưa hỗ trợ Badging API, gọi thẳng sẽ lỗi nếu không kiểm tra trước).
Future<void> setBadge(int count) async {
  if (!_navigator.hasProperty('setAppBadge'.toJS).toDart) return;
  try {
    if (count > 0) {
      await _navigator.setAppBadge(count).toDart;
    } else {
      await _navigator.clearAppBadge().toDart;
    }
  } catch (_) {
    // Trình duyệt báo hỗ trợ nhưng gọi lỗi (hiếm) — bỏ qua, badge không quan trọng bằng
    // việc app phải chạy tiếp bình thường.
  }
}
