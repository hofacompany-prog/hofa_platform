import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/env.dart';

/// Hiện phiên bản đang chạy — web dùng git commit hash lúc build (Env.appVersion, đối chiếu
/// nhanh với PWA update-check ở main.dart#_checkPwaVersion); bản NATIVE (Android/iOS cài từ
/// store) không có Env.appVersion (chỉ set lúc build web) nên đọc version+build number CÀI THẬT
/// trên máy qua package_info_plus — cùng số build dùng để so sánh ở AppUpdateService.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    if (kIsWeb) {
      return Text(
        'Phiên bản ${Env.appVersion}',
        textAlign: TextAlign.center,
        style: style,
      );
    }
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Text(
          info == null
              ? 'Đang tải phiên bản...'
              : 'Phiên bản ${info.version} (build ${info.buildNumber})',
          textAlign: TextAlign.center,
          style: style,
        );
      },
    );
  }
}
