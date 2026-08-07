import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

/// File này được đặt cạnh index.html để bản app cũ luôn kiểm tra được phiên bản
/// đang deploy, thay vì tin vào cache của chính nó.
class PwaVersionService {
  static Future<String?> fetchDeployedVersion() async {
    try {
      final uri = Uri.base.resolve(
        'app-version.json?checked_at=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(
        uri,
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      );
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      // Offline hay lỗi mạng không được chặn người quản trị dùng bản đang có.
      return null;
    }
  }

  /// Cache Storage tách biệt với localStorage/IndexedDB, nên việc này giữ nguyên
  /// phiên Supabase và token FCM nhưng buộc PWA tải lại toàn bộ asset mới.
  static Future<void> clearCacheAndReload() async {
    final caches = html.window.caches;
    if (caches != null) {
      final cacheNames = await caches.keys();
      await Future.wait(cacheNames.map(caches.delete));
    }
    html.window.location.reload();
  }
}
