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
    final canPromptNative = PwaInstallService.hasDeferredPrompt();
    // Ưu tiên tín hiệu SỐNG từ trình duyệt (hasDeferredPrompt) hơn cờ đã lưu trước đó
    // (wasInstalledPreviously) — trình duyệt CHỈ bắn lại beforeinstallprompt khi hiện KHÔNG
    // còn cài nữa (vd khách đã gỡ app ra), nên nếu tín hiệu đó đang có thì phải cho cài lại
    // ngay, không giữ mãi thông báo "đã cài rồi" cũ khiến không cài lại được (xem
    // web/index.html — beforeinstallprompt cũng tự xoá cờ localStorage cũ).
    final alreadyInstalled = !canPromptNative &&
        (_justInstalled || PwaInstallService.wasInstalledPreviously());

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
                    'Hãy thoát ra và mở app HOFA Tài xế ở màn hình chính để tiếp tục sử dụng.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    // Đã gỡ app rồi mà quay lại đây? Bấm để kiểm tra lại ngay, không cần tải
                    // lại cả trang — hữu ích khi trình duyệt bắn beforeinstallprompt hơi trễ
                    // sau khi màn này đã hiện sẵn.
                    onPressed: () => setState(() {}),
                    child: const Text('Đã gỡ app? Bấm để kiểm tra lại'),
                  ),
                ] else if (canPromptNative) ...[
                  Icon(Icons.install_mobile, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Cài đặt ứng dụng để tiếp tục!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bấm nút bên dưới để cài ứng dụng lên máy.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 32),
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
                    'Thoát ra màn hình vào app HOFA Tài xế để tiếp tục',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ] else ...[
                  // iOS không có API tự bật popup cài — đúng 3 bước thật trên Safari hiện nay:
                  // Chia sẻ -> Xem thêm (mục "Thêm vào MH chính" đã bị gộp vào đây từ vài bản
                  // iOS gần đây, không còn hiện thẳng ở hàng đầu) -> Thêm vào Màn hình chính.
                  Text(
                    'Làm theo 3 bước sau để cài đặt:',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  const _InstallStep(icon: Icons.ios_share, label: 'Nhấn Chia sẻ'),
                  const SizedBox(height: 16),
                  const _InstallStep(icon: Icons.expand_more, label: 'Xem thêm'),
                  const SizedBox(height: 16),
                  const _InstallStep(icon: Icons.add_box_outlined, label: 'Thêm vào Màn hình chính'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1 bước trong hướng dẫn "Chia sẻ → Xem thêm → Thêm vào Màn hình chính" trên iOS Safari —
/// icon riêng cho từng bước, khớp đúng icon thật trong bảng Chia sẻ của Safari.
class _InstallStep extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InstallStep({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
