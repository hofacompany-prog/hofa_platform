import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/user_device.dart';
import '../../providers/device_providers.dart';

/// Danh sách thiết bị đã đăng nhập tài khoản (bảng user_devices). "Gỡ thiết bị" xoá dòng này
/// VÀ ép đăng xuất từ xa thật — server chặn ngay request kế tiếp của đúng thiết bị đó
/// (DEVICE_REVOKED, xem middleware/auth.js), buộc app trên máy đó tự đăng xuất + xoá session
/// Supabase cục bộ. Không tức thời tuyệt đối (chờ tới request kế tiếp của máy đó, thường chỉ
/// vài giây tới vài phút nếu app đang mở), nhưng không cần máy đó đang online ngay lúc gỡ.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

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

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    UserDevice device,
    bool isCurrent,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gỡ thiết bị này?'),
        content: Text(
          isCurrent
              ? 'Đây chính là thiết bị bạn đang dùng để xem màn này — gỡ xong bạn sẽ bị đăng '
                    'xuất khỏi máy này ngay.'
              : '"${device.deviceName ?? 'Thiết bị không tên'}" sẽ bị đăng xuất và xoá session '
                    'đăng nhập trên máy đó ngay khi máy đó thực hiện thao tác kế tiếp (không '
                    'cần đang mở app ngay lúc này).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Gỡ thiết bị'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(deviceRepoProvider).remove(device.id);
      ref.invalidate(devicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gỡ thiết bị')),
        );
      }
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
    final devicesAsync = ref.watch(devicesProvider);
    final currentIdAsync = ref.watch(currentDeviceIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thiết bị đã đăng nhập')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(devicesProvider);
          ref.invalidate(currentDeviceIdProvider);
        },
        child: devicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Lỗi: $e')),
              ),
            ],
          ),
          data: (devices) {
            final currentId = currentIdAsync.valueOrNull;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Danh sách thiết bị đã đăng nhập tài khoản này. Gỡ 1 thiết bị sẽ '
                            'đăng xuất máy đó và xoá session đăng nhập trên máy đó ngay khi '
                            'máy đó thực hiện thao tác kế tiếp.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: [
                        Icon(
                          Icons.devices_other_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có thiết bị nào',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...devices.map((d) {
                    final isCurrent =
                        currentId != null && currentId == d.deviceId;
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: (isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline)
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    _platformIcon(d.platform),
                                    color: isCurrent
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              d.deviceName?.isNotEmpty == true
                                                  ? d.deviceName!
                                                  : 'Thiết bị không tên',
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isCurrent) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme
                                                    .colorScheme
                                                    .primary,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                'Thiết bị này',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        devicePlatformLabels[d.platform] ??
                                            d.platform ??
                                            'Không rõ nền tảng',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.outline,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            _InfoRow(
                              icon: Icons.schedule_outlined,
                              label: 'Hoạt động lần cuối',
                              value: formatDateTime(d.lastActiveAt),
                            ),
                            const SizedBox(height: 6),
                            _InfoRow(
                              icon: Icons.login_outlined,
                              label: 'Đăng nhập lần đầu',
                              value: formatDateTime(d.createdAt),
                            ),
                            const SizedBox(height: 6),
                            _InfoRow(
                              icon: d.hasPushToken
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_off_outlined,
                              label: 'Thông báo đẩy',
                              value: d.hasPushToken
                                  ? 'Đang bật'
                                  : 'Chưa cấp quyền/chưa đăng ký',
                              valueColor: d.hasPushToken
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.secondary,
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _confirmRemove(context, ref, d, isCurrent),
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                ),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                label: const Text('Gỡ thiết bị'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor,
              fontWeight: valueColor != null ? FontWeight.w600 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
