import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

/// Ép cập nhật bản NATIVE (Android/iOS cài từ CH Play/App Store) khi admin đánh dấu build hiện
/// tại quá cũ — riêng biệt hoàn toàn với PwaVersionService (chỉ có ý nghĩa trên web, so
/// Env.appVersion đóng cứng lúc build với app-version.json). Ở đây so build number CÀI THẬT trên
/// máy (package_info_plus đọc từ chính APK/IPA đã cài, không phải giá trị build-time) với
/// app_update_settings.min_build_number server cấu hình.
class AppUpdateService {
  AppUpdateService._();

  /// Không có nút bỏ qua/đóng — PopScope(canPop:false) + barrierDismissible:false, chỉ thoát
  /// được khi thật sự cập nhật rồi mở lại app (build number mới >= min_build_number, lần kiểm
  /// tra sau sẽ không hiện popup nữa). Gọi 1 lần lúc mở app (main.dart).
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;
    Map<String, dynamic>? settings;
    try {
      settings = await ApiClient.instance.get('/app-update-settings') as Map<String, dynamic>?;
    } catch (_) {
      return; // mất mạng/lỗi tạm thời — không chặn mở app vì 1 lần kiểm tra lỗi
    }
    if (settings == null) return;
    final minBuild = (settings['min_build_number'] as num?)?.toInt() ?? 1;
    final info = await PackageInfo.fromPlatform();
    final installedBuild = int.tryParse(info.buildNumber) ?? 0;
    if (installedBuild >= minBuild) return;
    if (!context.mounted) return;

    final storeUrl = defaultTargetPlatform == TargetPlatform.iOS
        ? settings['ios_store_url'] as String?
        : settings['android_store_url'] as String?;
    final versionLabel = settings['min_version_label'] as String?;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Cần cập nhật ứng dụng'),
          content: Text(
            (versionLabel == null || versionLabel.isEmpty)
                ? 'Đã có phiên bản mới — bạn cần cập nhật để tiếp tục sử dụng app. Bấm "Cập nhật '
                      'ngay" để mở kho ứng dụng.'
                : 'Phiên bản $versionLabel đã sẵn sàng — bạn cần cập nhật để tiếp tục sử dụng '
                      'app. Bấm "Cập nhật ngay" để mở kho ứng dụng.',
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
