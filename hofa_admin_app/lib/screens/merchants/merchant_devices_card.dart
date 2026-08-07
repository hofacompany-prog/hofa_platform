import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../models/merchant_device.dart';
import '../../providers/admin_providers.dart';

/// Danh sách thiết bị (điện thoại/trình duyệt) đang đăng nhập nhận thông báo của cửa hàng
/// này — gộp chung chủ + toàn bộ nhân viên (server/src/routes/merchants.js GET
/// /merchants/:id/devices, dùng lại push.resolveMerchantUserIds). Admin xem/tắt/xoá từng
/// thiết bị và chỉnh số thiết bị tối đa được đăng nhập cùng lúc (merchants.max_devices) —
/// vượt số này thì store app tự hỏi cửa hàng có muốn gỡ thiết bị cũ nhất để đăng nhập thiết
/// bị mới không (xem hofa_store_app/lib/core/push_service.dart _registerDevice).
class MerchantDevicesCard extends ConsumerStatefulWidget {
  final Merchant merchant;
  const MerchantDevicesCard({super.key, required this.merchant});

  @override
  ConsumerState<MerchantDevicesCard> createState() => _MerchantDevicesCardState();
}

class _MerchantDevicesCardState extends ConsumerState<MerchantDevicesCard> {
  late final TextEditingController _maxDevicesCtrl;
  bool _savingLimit = false;

  String get _merchantId => widget.merchant.id;

  @override
  void initState() {
    super.initState();
    _maxDevicesCtrl = TextEditingController(text: widget.merchant.maxDevices.toString());
  }

  @override
  void didUpdateWidget(covariant MerchantDevicesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.merchant.maxDevices != widget.merchant.maxDevices) {
      _maxDevicesCtrl.text = widget.merchant.maxDevices.toString();
    }
  }

  @override
  void dispose() {
    _maxDevicesCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLimit() async {
    final value = int.tryParse(_maxDevicesCtrl.text.trim());
    if (value == null || value < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập số nguyên từ 1 trở lên')),
      );
      return;
    }
    if (value == widget.merchant.maxDevices) return;
    setState(() => _savingLimit = true);
    try {
      await ref.read(adminRepoProvider).updateMerchant(_merchantId, {'max_devices': value});
      ref.invalidate(merchantDetailProvider(_merchantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu giới hạn thiết bị')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingLimit = false);
    }
  }

  Future<void> _disable(MerchantDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tắt thiết bị này?'),
        content: Text(
          'Ngừng gửi thông báo tới "${d.deviceName?.isNotEmpty == true ? d.deviceName : 'Thiết bị không tên'}" '
          'của ${d.userFullName}. Thiết bị vẫn đăng nhập bình thường, chỉ không nhận thông báo nữa.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Tắt')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepoProvider).disableMerchantDevice(_merchantId, d.id);
      ref.invalidate(merchantDevicesProvider(_merchantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _delete(MerchantDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá thiết bị này?'),
        content: Text(
          'Xoá hẳn "${d.deviceName?.isNotEmpty == true ? d.deviceName : 'Thiết bị không tên'}" '
          'của ${d.userFullName} khỏi danh sách — không đăng xuất được tài khoản đó từ xa, chỉ '
          'ngừng nhận thông báo và giải phóng 1 chỗ trong giới hạn thiết bị.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepoProvider).deleteMerchantDevice(_merchantId, d.id);
      ref.invalidate(merchantDevicesProvider(_merchantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devicesAsync = ref.watch(merchantDevicesProvider(_merchantId));

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
                Icon(Icons.devices_other_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Thiết bị đăng nhập', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Thiết bị của chủ và nhân viên cửa hàng đang nhận thông báo đơn hàng. '
              'Xoá không đăng xuất được từ xa — chỉ ngừng gửi thông báo tới máy đó.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _maxDevicesCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Giới hạn thiết bị',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _savingLimit ? null : _saveLimit,
                  child: _savingLimit
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Lưu'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Vượt số này, app cửa hàng sẽ hỏi có muốn gỡ thiết bị cũ nhất để đăng nhập '
              'thiết bị mới không.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const Divider(height: 32),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  );
                }
                return Column(
                  children: devices
                      .map(
                        (d) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(_platformIcon(d.platform), color: theme.colorScheme.outline),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            d.deviceName?.isNotEmpty == true
                                                ? d.deviceName!
                                                : 'Thiết bị không tên',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          label: Text(
                                            merchantUserRoleLabels[d.userRole] ?? d.userRole,
                                            style: theme.textTheme.labelSmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${d.userFullName} · '
                                      '${merchantDevicePlatformLabels[d.platform] ?? d.platform ?? 'Không rõ'}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      d.lastActiveAt != null
                                          ? 'Hoạt động lần cuối: ${formatDateTime(d.lastActiveAt!)}'
                                          : 'Chưa có hoạt động',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    Text(
                                      d.hasPushToken ? 'Thông báo: đang bật' : 'Thông báo: đã tắt',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: d.hasPushToken
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.secondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (d.hasPushToken)
                                IconButton(
                                  tooltip: 'Tắt thông báo',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                                  onPressed: () => _disable(d),
                                ),
                              IconButton(
                                tooltip: 'Xoá thiết bị',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _delete(d),
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
