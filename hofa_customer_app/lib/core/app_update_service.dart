import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

/// So 2 chuỗi phiên bản dạng "X.Y.Z" theo từng đoạn số (không phải so chuỗi thô — "2.9.0" phải
/// lớn hơn "2.10.0" mới đúng dù so chuỗi thì ngược lại) — trả về true nếu [installed] < [min].
/// Đoạn thiếu (vd "2.2" so với "2.2.1") coi như 0.
bool _isOlderThan(String installed, String min) {
  List<int> parse(String v) => v
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final a = parse(installed);
  final b = parse(min);
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// Ép cập nhật bản NATIVE (Android/iOS cài từ CH Play/App Store) khi admin đánh dấu phiên bản
/// hiện tại quá cũ — riêng biệt hoàn toàn với PwaVersionService (chỉ có ý nghĩa trên web, so
/// Env.appVersion đóng cứng lúc build với app-version.json). Ở đây so PHIÊN BẢN (version: X.Y.Z
/// trong pubspec.yaml — đúng số hiện trên App Store/CH Play) CÀI THẬT trên máy (package_info_plus
/// đọc từ chính APK/IPA đã cài) với app_update_settings.min_version_label server cấu hình — CỐ
/// Ý không dùng build number (nội bộ, không có ý nghĩa gì với khách thật, chưa kể App Store còn
/// "đóng" 1 version cũ lại không cho nộp thêm build nên build number của 1 lần nộp có thể không
/// bao giờ thực sự lên máy khách).
class AppUpdateService {
  AppUpdateService._();

  /// Không có nút bỏ qua/đóng — PopScope(canPop:false) + barrierDismissible:false, chỉ thoát
  /// được khi thật sự cập nhật rồi mở lại app (phiên bản mới >= min_version_label, lần kiểm tra
  /// sau sẽ không hiện popup nữa). Gọi 1 lần lúc mở app (main.dart).
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;
    Map<String, dynamic>? settings;
    try {
      settings = await ApiClient.instance.get('/app-update-settings') as Map<String, dynamic>?;
    } catch (_) {
      return; // mất mạng/lỗi tạm thời — không chặn mở app vì 1 lần kiểm tra lỗi
    }
    if (settings == null) return;
    final minVersion = settings['min_version_label'] as String?;
    if (minVersion == null || minVersion.trim().isEmpty) return; // admin chưa cấu hình — bỏ qua

    final info = await PackageInfo.fromPlatform();
    if (!_isOlderThan(info.version, minVersion.trim())) return;
    if (!context.mounted) return;

    final storeUrl = defaultTargetPlatform == TargetPlatform.iOS
        ? settings['ios_store_url'] as String?
        : settings['android_store_url'] as String?;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Cần cập nhật ứng dụng'),
          content: Text(
            'Phiên bản $minVersion đã sẵn sàng — bạn cần cập nhật để tiếp tục sử dụng app. Bấm '
            '"Cập nhật ngay" để mở kho ứng dụng.',
          ),
          actions: [
            FilledButton(
              onPressed: (storeUrl == null || storeUrl.isEmpty)
                  ? null
                  : () async {
                      final uri = Uri.parse(storeUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
              child: const Text('Cập nhật ngay'),
            ),
          ],
        ),
      ),
    );
  }
}
