import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

Future<String?> fetchDeployedVersion() async {
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
    // Offline hay lỗi mạng không được chặn người dùng dùng bản đang có.
    return null;
  }
}

/// Gỡ các service worker cache asset cũ của Flutter (từ bản build trước khi tắt
/// --pwa-strategy) — bản build mới không đăng ký lại nó nữa nên nó sẽ đứng yên mãi nếu không
/// gỡ tay, tranh giành scope gốc với firebase-messaging-sw.js và gây push đến chập chờn/lặp.
/// firebase-messaging-sw.js không đụng tới, vẫn phải sống để nhận push tiếp.
///
/// Gọi UNCONDITIONALLY mỗi lần mở app (main.dart), không chỉ lúc người dùng bấm "Cập nhật
/// ngay" — nếu không, máy nào đã cài PWA từ trước khi --pwa-strategy=none ra đời và từ đó
/// đến giờ chưa từng thấy đúng lúc bản build lệch version (để hiện nút đó) thì service worker
/// cũ cứ nằm ỳ mãi, âm thầm phá hỏng mọi bản vá liên quan tới push sau này dù code đã đúng.
Future<void> unregisterStaleServiceWorkers() async {
  final container = html.window.navigator.serviceWorker;
  if (container == null) return;
  final registrations = await container.getRegistrations();
  for (final registration in registrations) {
    final scriptUrl = registration.active?.scriptURL ??
        registration.waiting?.scriptURL ??
        registration.installing?.scriptURL ??
        '';
    if (scriptUrl.contains('flutter_service_worker.js')) {
      await registration.unregister();
    }
  }
}

/// Cache Storage tách biệt với localStorage/IndexedDB, nên việc này giữ nguyên
/// phiên Supabase và token FCM nhưng buộc PWA tải lại toàn bộ asset mới.
Future<void> clearCacheAndReload() async {
  final caches = html.window.caches;
  if (caches != null) {
    final cacheNames = await caches.keys();
    await Future.wait(cacheNames.map(caches.delete));
  }
  try {
    await unregisterStaleServiceWorkers();
  } catch (_) {
    // Không chặn luồng cập nhật chính nếu gỡ service worker cũ thất bại.
  }
  html.window.location.reload();
}
