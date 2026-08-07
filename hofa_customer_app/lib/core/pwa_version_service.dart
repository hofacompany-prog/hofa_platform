import 'pwa_version_service_stub.dart'
    if (dart.library.html) 'pwa_version_service_web.dart' as impl;

/// File `app-version.json` được đặt cạnh index.html để bản PWA cũ luôn kiểm tra được
/// phiên bản đang deploy, thay vì tin vào cache của chính nó. Chỉ có ý nghĩa trên web —
/// bản Android không có khái niệm cache PWA nên các hàm này là no-op ngoài web
/// (xem pwa_version_service_stub.dart).
class PwaVersionService {
  static Future<String?> fetchDeployedVersion() => impl.fetchDeployedVersion();

  static Future<void> clearCacheAndReload() => impl.clearCacheAndReload();
}
