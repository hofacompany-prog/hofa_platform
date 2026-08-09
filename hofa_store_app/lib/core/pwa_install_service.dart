import 'pwa_install_service_stub.dart'
    if (dart.library.html) 'pwa_install_service_web.dart' as impl;

/// Popup gợi ý "Thêm vào màn hình chính" (cài PWA) — hỏi lại MỖI LẦN mở app cho tới khi máy
/// đã cài xong (không nhớ trạng thái "đã từ chối"), chỉ có ý nghĩa trên web — bản Android cài
/// qua store/APK nên các hàm này là no-op ngoài web (xem pwa_install_service_stub.dart).
class PwaInstallService {
  /// Đã chạy ở chế độ standalone (đã cài lên máy) chưa — true thì không hỏi nữa.
  static bool isStandalone() => impl.isStandalone();

  /// Safari trên iPhone/iPad — trình duyệt DUY NHẤT trên iOS hỗ trợ "Thêm vào MH chính", và
  /// không có API để tự bật popup cài như Chrome/Edge, phải hướng dẫn tay qua nút Chia sẻ.
  static bool isIOSSafari() => impl.isIOSSafari();

  /// Trình duyệt bên thứ 3 (Chrome/Cốc Cốc...) trên iOS — không cài PWA được, chỉ nên hướng
  /// dẫn đổi sang Safari.
  static bool isIOSNonSafari() => impl.isIOSNonSafari();

  /// Trình duyệt đã bắn sự kiện beforeinstallprompt (đủ điều kiện cài, có thể tự bật popup) —
  /// xem web/index.html.
  static bool hasDeferredPrompt() => impl.hasDeferredPrompt();

  /// Bật popup cài đặt gốc của trình duyệt — trả về 'accepted' | 'dismissed' | 'unavailable'.
  static Future<String> promptInstall() => impl.promptInstall();
}
