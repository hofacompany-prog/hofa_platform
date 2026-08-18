import 'package:flutter/material.dart';
import '../core/pwa_install_service.dart';

/// Popup nhắc cài PWA — trước đây là 1 màn hình CHẶN CỨNG (InstallPwaScreen, chặn ở
/// router.dart), giờ chỉ là popup nhắc định kỳ (xem CustomerShell), tự đóng được (bấm ra
/// ngoài/nút X), không chặn luồng dùng app. Chỉ còn 2 nhánh nội dung (Android có thể tự bật
/// popup cài / iOS hướng dẫn tay) — nhánh "đã cài rồi" không cần nữa vì CustomerShell đã tự
/// ngừng gọi hàm này khi PwaInstallService.wasInstalledPreviously() true.
Future<void> showInstallPwaDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _InstallPwaDialog(),
  );
}

class _InstallPwaDialog extends StatefulWidget {
  const _InstallPwaDialog();

  @override
  State<_InstallPwaDialog> createState() => _InstallPwaDialogState();
}

class _InstallPwaDialogState extends State<_InstallPwaDialog> {
  bool _installing = false;

  Future<void> _install() async {
    setState(() => _installing = true);
    final outcome = await PwaInstallService.promptInstall();
    if (!mounted) return;
    if (outcome == 'accepted') {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cài đặt xong! Mở app HOFA ở màn hình chính để tiếp tục.'),
        ),
      );
      return;
    }
    setState(() => _installing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPromptNative = PwaInstallService.hasDeferredPrompt();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cài đặt app HOFA',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (canPromptNative) ...[
                Icon(
                  Icons.install_mobile,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cài lên màn hình chính để mở nhanh hơn, không cần mở trình duyệt mỗi lần.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _installing ? null : _install,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _installing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cài đặt ngay'),
                  ),
                ),
              ] else ...[
                Text(
                  'Làm theo 3 bước sau để cài đặt:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _InstallStep(
                  icon: Icons.ios_share,
                  label: 'Nhấn Chia sẻ',
                  note: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      children: [
                        const TextSpan(text: 'Bấm trên thanh trình duyệt — '),
                        TextSpan(
                          text: 'Không phải bấm ở đây!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const _InstallStep(icon: Icons.expand_more, label: 'Xem thêm'),
                const SizedBox(height: 14),
                const _InstallStep(
                  icon: Icons.add_box_outlined,
                  label: 'Thêm vào Màn hình chính',
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Để sau'),
                ),
              ),
            ],
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
  final Widget? note;
  const _InstallStep({required this.icon, required this.label, this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (note != null) ...[const SizedBox(height: 2), note!],
            ],
          ),
        ),
      ],
    );
  }
}
