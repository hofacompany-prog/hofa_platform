import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/app_version_text.dart';
import '../../widgets/branch_break_dialogs.dart';
import '../../widgets/nav_back_button.dart';
import '../../widgets/permission_settings_section.dart';
import '../../widgets/stat_card.dart';

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
              'Toàn bộ hồ sơ cửa hàng sẽ bị xoá vĩnh viễn và không đăng nhập lại được bằng số '
              'điện thoại này nữa. Lịch sử đơn hàng vẫn được giữ lại (ẩn danh) để đối chiếu '
              'doanh thu/kế toán.',
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

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return MerchantRepository().branches(merchant.id);
});

class BranchSettingsScreen extends ConsumerWidget {
  const BranchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(myMerchantProvider);
    final branchesAsync = ref.watch(_branchesProvider);
    // Quản lý nhân viên chỉ dành cho chủ cửa hàng — merchant_staff (dù có quyền gì) không
    // được thêm/sửa/xoá nhân viên khác, xem requireOwnerAccess ở server.
    final isOwner =
        ref.watch(userProfileProvider).valueOrNull?.role == 'merchant_owner';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Cài đặt'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                merchantAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, _) => const SizedBox(),
                  data: (m) => m == null
                      ? const SizedBox()
                      : Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      backgroundImage: m.logoUrl != null
                                          ? NetworkImage(m.logoUrl!)
                                          : null,
                                      child: m.logoUrl == null
                                          ? Icon(
                                              Icons.storefront,
                                              color: theme.colorScheme.primary,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.name,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          Text(
                                            'Trạng thái: ${m.status} · Hoa hồng: ${m.commissionRate}%',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Đơn tối thiểu: ${formatVnd(m.minOrderAmount)} · TG chuẩn bị: ${m.avgPrepMinutes} phút',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => context.push(
                                    '/settings/profile',
                                    extra: m,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Sửa hồ sơ cửa hàng'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Text('Chi nhánh', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                branchesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (branches) => Column(
                    children: branches
                        .map(
                          (b) => Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile(
                                    title: Text(b.name),
                                    subtitle: Text(
                                      b.status == 'on_break'
                                          ? (b.breakUntil != null
                                                ? 'Tạm nghỉ đến ${formatBreakUntil(b.breakUntil!)}'
                                                : 'Tạm nghỉ')
                                          : b.status == 'closed_hours'
                                          ? 'Ngoài giờ hoạt động'
                                          : (b.fullLine.isEmpty
                                                ? '${b.line1}, ${b.province}'
                                                : b.fullLine),
                                    ),
                                    value: b.status != 'on_break',
                                    onChanged: (val) async {
                                      try {
                                        if (!val) {
                                          final until = await pickBreakDuration(
                                            context,
                                          );
                                          if (until == null) return;
                                          await MerchantRepository()
                                              .toggleBranchOpen(
                                                b.id,
                                                false,
                                                breakUntil: until,
                                              );
                                        } else {
                                          final ok = await confirmReopenNow(
                                            context,
                                          );
                                          if (!ok) return;
                                          await MerchantRepository()
                                              .toggleBranchOpen(b.id, true);
                                        }
                                        ref.invalidate(_branchesProvider);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text('Lỗi: $e')),
                                          );
                                        }
                                      }
                                    },
                                    secondary: Icon(
                                      b.status == 'open'
                                          ? Icons.storefront
                                          : Icons.storefront_outlined,
                                      color: switch (b.status) {
                                        'on_break' => Colors.red,
                                        'closed_hours' => Colors.grey,
                                        _ => Colors.green,
                                      },
                                    ),
                                  ),
                                  SwitchListTile(
                                    title: const Text('Tự động nhận đơn'),
                                    subtitle: const Text(
                                      'Bật: vẫn hiện màn nhận đơn, đếm ngược bằng màu trên thanh trượt — hết giờ hệ thống tự nhận hộ.\n'
                                      'Tắt: có ít phút để tự xác nhận thủ công — hết giờ đơn tự huỷ và chi nhánh tự đóng cửa.\n'
                                      '(Số phút cụ thể do HOFA cấu hình chung cho toàn hệ thống.)',
                                    ),
                                    value: b.autoAcceptOrders,
                                    onChanged: (val) async {
                                      try {
                                        await MerchantRepository()
                                            .setAutoAcceptOrders(b.id, val);
                                        ref.invalidate(_branchesProvider);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text('Lỗi: $e')),
                                          );
                                        }
                                      }
                                    },
                                    secondary: const Icon(Icons.bolt_outlined),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => context.push(
                                            '/settings/branches/${b.id}',
                                            extra: b,
                                          ),
                                          icon: const Icon(
                                            Icons.edit_location_alt_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Sửa địa chỉ'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => context.push(
                                            '/settings/branches/${b.id}/hours',
                                            extra: b.name,
                                          ),
                                          icon: const Icon(
                                            Icons.schedule_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Giờ mở cửa'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tắt công tắc khi hết hàng hoặc nghỉ đột xuất — cửa hàng sẽ tạm ngừng nhận đơn mới.',
                  style: TextStyle(color: Colors.grey),
                ),
                if ((branchesAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 16),
                  StatCard(
                    label: 'Tổng chi nhánh',
                    value: '${branchesAsync.valueOrNull!.length}',
                    icon: Icons.storefront_outlined,
                  ),
                ],
                if (isOwner) ...[
                  const SizedBox(height: 24),
                  Text('Nhân viên', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: ListTile(
                      onTap: () => context.push('/settings/staff'),
                      leading: Icon(
                        Icons.badge_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Quản lý nhân viên'),
                      subtitle: const Text(
                        'Thêm nhân viên, phân quyền được làm gì trong app',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Bảo mật', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: ListTile(
                    onTap: () => context.push('/settings/devices'),
                    leading: Icon(
                      Icons.devices_other_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Thiết bị đã đăng nhập'),
                    subtitle: const Text(
                      'Xem và gỡ các thiết bị đang nhận thông báo',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 24),
                const PermissionSettingsSection(),
                const SizedBox(height: 24),
                // Bottom bar mobile không có nút đăng xuất riêng (khác NavigationRail ở màn
                // rộng đã có sẵn icon logout) — đây là cách duy nhất đăng xuất được trên điện
                // thoại, nên để màu nổi bật (error) thay vì lẫn vào các nút khác.
                FilledButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _deleteAccount(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Xoá tài khoản'),
                ),
                const SizedBox(height: 12),
                const AppVersionText(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
