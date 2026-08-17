import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'pwa_install_service.dart';

/// Cùng triết lý requireLogin.dart — khách lướt/chọn món tự do, chỉ chặn bắt cài PWA ĐÚNG lúc
/// bấm hành động thật sự cần tài khoản (đặt hàng...), không chặn ngay từ đầu ở router nữa (xem
/// router.dart, pwaProtectedPaths). Gọi TRƯỚC requireLogin ở cùng 1 nút bấm — đặt hàng ngay
/// trong app đã cài PWA thì mới đáng tin cậy nhận được thông báo trạng thái đơn qua push, nên
/// ưu tiên hỏi cài trước rồi mới hỏi đăng nhập.
Future<bool> requirePwaInstall(BuildContext context) async {
  final needsInstall =
      !PwaInstallService.isStandalone() &&
      (PwaInstallService.wasInstalledPreviously() ||
          PwaInstallService.hasDeferredPrompt() ||
          PwaInstallService.isIOS());
  if (!needsInstall) return true;

  if (context.mounted) context.push('/install-pwa');
  return false;
}
