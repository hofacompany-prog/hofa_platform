import 'package:flutter/material.dart';
import 'env.dart';
import 'pwa_version_service_stub.dart'
    if (dart.library.html) 'pwa_version_service_web.dart' as impl;

/// File `app-version.json` được đặt cạnh index.html để bản PWA cũ luôn kiểm tra được
/// phiên bản đang deploy, thay vì tin vào cache của chính nó. Chỉ có ý nghĩa trên web —
/// bản Android không có khái niệm cache PWA nên các hàm này là no-op ngoài web
/// (xem pwa_version_service_stub.dart).
class PwaVersionService {
  static Future<String?> fetchDeployedVersion() => impl.fetchDeployedVersion();

  static Future<void> clearCacheAndReload() => impl.clearCacheAndReload();

  static Future<void> unregisterStaleServiceWorkers() => impl.unregisterStaleServiceWorkers();

  /// So Env.appVersion (đóng cứng lúc build) với app-version.json (đọc runtime) — hiện popup
  /// "Đã có phiên bản mới" (không cho bấm ra ngoài, chỉ có nút "Cập nhật ngay") nếu lệch. Dùng
  /// chung cho cả 2 nơi: main.dart tự gọi lúc mở app, và nút "Kiểm tra cập nhật" ở màn Tài
  /// khoản để khách tự bấm kiểm tra bất cứ lúc nào. Trả về true nếu phát hiện có bản mới (đã
  /// hiện popup) — nơi gọi tự quyết định có cần báo thêm "đã là bản mới nhất" khi trả về false
  /// hay không (main.dart lúc mở app thì im lặng, nút bấm tay thì nên báo cho khách biết).
  static Future<bool> checkForUpdate(BuildContext context) async {
    unregisterStaleServiceWorkers().catchError((_) {});
    final deployedVersion = await fetchDeployedVersion();
    if (deployedVersion == null || deployedVersion == Env.appVersion) return false;
    if (!context.mounted) return false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Đã có phiên bản mới'),
        content: Text(
          'Phiên bản $deployedVersion đã sẵn sàng. Cập nhật để tải dữ liệu và giao diện mới nhất.',
        ),
        actions: [
          FilledButton(
            onPressed: clearCacheAndReload,
            child: const Text('Cập nhật ngay'),
          ),
        ],
      ),
    );
    return true;
  }
}
