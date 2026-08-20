import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/user_device.dart';
import '../../providers/admin_providers.dart';

/// Danh sách thiết bị đang đăng nhập của 1 người dùng bất kỳ (khách, tài xế, chủ/nhân viên cửa
/// hàng...) — GET/DELETE /admin/users/:id/devices, cùng cơ chế gỡ với màn "Thiết bị đã đăng
/// nhập" tự phục vụ ở app cửa hàng (chỉ chặn được request KẾ TIẾP của máy đó, không thu hồi
/// access_token hiện có ngay lập tức).
class UserDevicesCard extends ConsumerWidget {
  final String userId;
  const UserDevicesCard({super.key, required this.userId});

  IconData _platformIcon(String? platform) {
    switch (platform) {
      case 'ios':
        return Icons.phone_iphone_outlined;
      case 'android':
        return Icons.phone_android_outlined;
      default:
        return Icons.computer_outlined;
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, UserDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gỡ thiết bị này?'),
        content: Text(
          'Xoá "${d.deviceName?.isNotEmpty == true ? d.deviceName : 'Thiết bị không tên'}" — '
          'thiết bị đó sẽ bị đăng xuất và xoá session đăng nhập ngay khi thực hiện thao tác kế '
          'tiếp (không cần đang mở app ngay lúc này).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gỡ thiết bị'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepoProvider).removeUserDevice(userId, d.id);
      ref.invalidate(userDevicesProvider(userId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devicesAsync = ref.watch(userDevicesProvider(userId));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.devices_other_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Thiết bị đã đăng nhập', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Thiết bị người dùng này đang đăng nhập/nhận thông báo. Gỡ 1 thiết bị sẽ đăng '
              'xuất máy đó từ xa.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            devicesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Lỗi: $e'),
              data: (devices) {
                if (devices.isEmpty) {
                  return Text(
                    'Chưa có thiết bị nào đăng nhập.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  );
                }
                return Column(
                  children: devices
                      .map(
                        (d) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _platformIcon(d.platform),
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.deviceName?.isNotEmpty == true
                                          ? d.deviceName!
                                          : 'Thiết bị không tên',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      devicePlatformLabels[d.platform] ??
                                          d.platform ??
                                          'Không rõ',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Hoạt động lần cuối: ${formatDateTime(d.lastActiveAt)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                    Text(
                                      d.hasPushToken
                                          ? 'Thông báo: đang bật'
                                          : 'Thông báo: đã tắt',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: d.hasPushToken
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.secondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Gỡ thiết bị',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () => _remove(context, ref, d),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
