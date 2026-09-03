import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/app_version_text.dart';
import '../../widgets/permission_settings_section.dart';

/// Yêu cầu xoá tài khoản — không thể hoàn tác nên bắt gõ đúng chữ "XOÁ" để xác nhận (nặng tay
/// hơn dialog Huỷ/Xoá thường, tránh bấm nhầm khi đây là hành động huỷ hẳn tài khoản). Tài khoản
/// không còn tự đăng ký được trong app (xem login_screen.dart) nhưng vẫn cần nút xoá — App
/// Store/CH Play yêu cầu có cách xoá tài khoản cho mọi app có khái niệm tài khoản, không riêng
/// app có tự đăng ký.
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final confirmCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Xoá tài khoản?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Toàn bộ hồ sơ tài xế sẽ bị xoá vĩnh viễn và không đăng nhập lại được bằng số '
              'điện thoại này nữa. Lịch sử chuyến giao vẫn được giữ lại (ẩn danh) để đối chiếu '
              'thu nhập/kế toán.',
            ),
            const SizedBox(height: 16),
            const Text('Gõ "XOÁ" để xác nhận:'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              autofocus: true,
              onChanged: (_) => setDialogState(() {}),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: confirmCtrl.text.trim().toUpperCase() == 'XOÁ'
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await UserRepository().deleteAccount();
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // đóng loading
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // đóng loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final driverAsync = ref.watch(myDriverProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                            child: Icon(Icons.person, color: theme.colorScheme.primary, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.fullName, style: theme.textTheme.titleMedium),
                                Text(profile.phone, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      driverAsync.when(
                        loading: () => const SizedBox(),
                        error: (_, _) => const SizedBox(),
                        data: (driver) => driver == null
                            ? const SizedBox()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _row(context, 'Loại xe', driver.vehicleType ?? '—'),
                                  _row(context, 'Biển số', driver.vehiclePlate ?? '—'),
                                  _row(
                                    context,
                                    'Trạng thái hồ sơ',
                                    driver.isVerified
                                        ? 'Đã duyệt'
                                        : (driver.isRejected ? 'Bị từ chối' : 'Chờ duyệt'),
                                  ),
                                  _row(context, 'Ngân hàng', driver.bankName ?? '—'),
                                  _row(context, 'Số tài khoản', driver.bankAccountNumber ?? '—'),
                                  _row(context, 'Đánh giá', '${driver.ratingAvg}★ (${driver.ratingCount} lượt)'),
                                  _row(context, 'Tổng chuyến', '${driver.totalDeliveries}'),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const PermissionSettingsSection(),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.push('/edit-driver-profile'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Sửa hồ sơ'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _deleteAccount(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Xoá tài khoản'),
              ),
              const SizedBox(height: 12),
              const AppVersionText(),
            ],
          );
        },
      ),
    );
  }
}
