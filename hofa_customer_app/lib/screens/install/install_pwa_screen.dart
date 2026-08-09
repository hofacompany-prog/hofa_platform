import 'package:flutter/material.dart';
import '../../core/pwa_install_service.dart';

/// Màn hình bắt buộc cài PWA — thay thế TOÀN BỘ app (kể cả màn đăng nhập) cho tới khi máy cài
/// xong, chặn ở router.dart (redirect), không có nút "bỏ qua" như popup trước đây. Chỉ vào
/// được màn này khi trình duyệt thực sự có cách cài (Android/Chrome có beforeinstallprompt,
/// hoặc bất kỳ trình duyệt nào trên iOS) HOẶC đã từng cài trước đó nhưng đang mở lại bằng
/// trình duyệt thường — xem điều kiện needsInstall ở router.dart; trình duyệt desktop không hỗ
/// trợ cài kiểu này (Firefox, Safari desktop...) không bị chặn.
///
/// KHÔNG tự điều hướng đi đâu sau khi cài xong (context.go) — vẫn đang ở trong tab trình duyệt
/// cũ, chưa chắc đã standalone=true ngay (chỉ đúng khi mở lại từ icon mới), tự điều hướng dễ
/// bị router đá ngược lại đúng màn này (kẹt lại) nếu trình duyệt chưa kịp cập nhật trạng thái.
/// Thay vào đó chỉ báo "đã cài xong, thoát ra mở app" và dừng — an toàn tuyệt đối, không bao
/// giờ kẹt.
class InstallPwaScreen extends StatefulWidget {
  const InstallPwaScreen({super.key});

  @override
  State<InstallPwaScreen> createState() => _InstallPwaScreenState();
}

class _InstallPwaScreenState extends State<InstallPwaScreen> {
  bool _installing = false;
  bool _justInstalled = false;

  Future<void> _install() async {
    setState(() => _installing = true);
    final outcome = await PwaInstallService.promptInstall();
    if (!mounted) return;
    setState(() {
      _installing = false;
      _justInstalled = outcome == 'accepted';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Đã cài (vừa xong trong phiên này, hoặc appinstalled đã bắn từ trước — xem
    // PwaInstallService.wasInstalledPreviously) nhưng vẫn đang ở trong trình duyệt thường
    // (chưa mở từ icon màn hình chính) — chỉ còn việc nhắc thoát ra, không hỏi cài lại nữa.
    final alreadyInstalled = _justInstalled || PwaInstallService.wasInstalledPreviously();
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
                if (alreadyInstalled) ...[
                  Icon(Icons.check_circle_outline, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Đã cài đặt xong!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hãy thoát ra và mở app HOFA ở màn hình chính để tiếp tục sử dụng.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ] else ...[
                  Icon(
                    canPromptNative ? Icons.install_mobile : Icons.ios_share,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    canPromptNative ? 'Cài đặt ứng dụng để tiếp tục!' : 'Hãy thêm vào Màn hình chính!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: canPromptNative ? null : theme.colorScheme.secondary,
                    ),
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
                  if (canPromptNative) ...[
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
                    const SizedBox(height: 16),
                    Text(
                      'Thoát ra màn hình vào app HOFA để tiếp tục',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
