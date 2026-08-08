import 'package:flutter/material.dart';
import '../core/env.dart';

/// Hiện phiên bản đang chạy (git commit hash lúc build, xem core/env.dart) — đối chiếu nhanh
/// với PWA update-check (main.dart#_checkPwaVersion) khi cần biết máy đã cập nhật hay chưa.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Phiên bản ${Env.appVersion}',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
    );
  }
}
