import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/pwa_install_service.dart';

/// Màn hình bắt buộc cài PWA — thay thế TOÀN BỘ app (kể cả màn đăng nhập) cho tới khi máy cài
/// xong, chặn ở router.dart (redirect), không có nút "bỏ qua" như popup trước đây. Chỉ vào
/// được màn này khi trình duyệt thực sự có cách cài (Android/Chrome có beforeinstallprompt,
/// hoặc bất kỳ trình duyệt nào trên iOS) — xem điều kiện needsInstall ở router.dart; trình
/// duyệt desktop không hỗ trợ cài kiểu này (Firefox, Safari desktop...) không bị chặn.
class InstallPwaScreen extends StatefulWidget {
  const InstallPwaScreen({super.key});

  @override
  State<InstallPwaScreen> createState() => _InstallPwaScreenState();
}

class _InstallPwaScreenState extends State<InstallPwaScreen> {
  bool _installing = false;

  Future<void> _install() async {
    setState(() => _installing = true);
    final outcome = await PwaInstallService.promptInstall();
    if (!mounted) return;
    setState(() => _installing = false);
    // Đã chấp nhận cài — không thể tự biết standalone=true ngay trong tab trình duyệt hiện
    // tại (chỉ đúng khi mở lại từ icon mới), nhưng "accepted" đã là tín hiệu đủ chắc để cho
    // vào tiếp, không bắt chờ thêm.
    if (outcome == 'accepted' && context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPromptNative = PwaInstallService.hasDeferredPrompt();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 96),
                const SizedBox(height: 16),
                Text(
                  'Mua hộ, có HOFA',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 40),
                Icon(
                  canPromptNative ? Icons.install_mobile : Icons.ios_share,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  canPromptNative ? 'Cài đặt ứng dụng để tiếp tục!' : 'Hãy thêm vào Màn hình chính!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  canPromptNative
                      ? 'Bấm nút bên dưới để cài ứng dụng lên máy.'
                      : 'Nhấn nút Chia sẻ ở thanh trình duyệt, rồi chọn "Thêm vào MH chính".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 32),
                if (canPromptNative)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _installing ? null : _install,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                      child: _installing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Cài đặt ngay',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
