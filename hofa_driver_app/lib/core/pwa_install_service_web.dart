import 'dart:html' as html;
import 'dart:js_interop';

// beforeinstallprompt không có typing chuẩn — window.__hofaPwaDeferredPrompt được set từ
// script tay trong web/index.html (bắt sự kiện NGAY từ đầu, trước khi Flutter kịp tải xong,
// vì trình duyệt chỉ bắn sự kiện này đúng 1 lần). dart:js_interop (không phải dart:js_util,
// đã bị gỡ khỏi SDK) dùng để đọc lại + gọi .prompt() trên đối tượng JS đó.
@JS('window.__hofaPwaDeferredPrompt')
external JSAny? get _deferredPromptRaw;

@JS('window.__hofaPwaDeferredPrompt')
external set _deferredPromptRaw(JSAny? value);

// navigator.standalone: cách DUY NHẤT nhận biết app đã "Thêm vào MH chính" trên iOS Safari —
// không có trong chuẩn Web/dart:html.
@JS('window.navigator.standalone')
external bool? get _iosStandalone;

extension type _DeferredPromptEvent(JSObject _) implements JSObject {
  external void prompt();
  external JSPromise<JSObject> get userChoice;
}

extension type _UserChoice(JSObject _) implements JSObject {
  external String get outcome;
}

bool isStandalone() {
  try {
    final standaloneMedia = html.window.matchMedia('(display-mode: standalone)').matches;
    return standaloneMedia || (_iosStandalone ?? false);
  } catch (_) {
    return false;
  }
}

/// Bất kỳ trình duyệt nào trên iPhone/iPad (Safari, Chrome, Cốc Cốc, Firefox...) — không
/// riêng Safari nữa: không trình duyệt iOS nào có beforeinstallprompt (kể cả Chrome-iOS, vì
/// đều chỉ là "vỏ" giao diện quanh WebKit của Safari), nên tất cả đều dùng chung hướng dẫn tay
/// "Nhấn nút Chia sẻ, rồi chọn Thêm vào MH chính".
bool isIOS() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
}

bool hasDeferredPrompt() {
  try {
    return _deferredPromptRaw != null;
  } catch (_) {
    return false;
  }
}

Future<String> promptInstall() async {
  try {
    final raw = _deferredPromptRaw;
    if (raw == null) return 'unavailable';
    final event = _DeferredPromptEvent(raw as JSObject);
    event.prompt();
    final choice = await event.userChoice.toDart;
    final outcome = _UserChoice(choice).outcome;
    _deferredPromptRaw = null;
    return outcome;
  } catch (_) {
    return 'unavailable';
  }
}
