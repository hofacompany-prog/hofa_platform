import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../widgets/app_version_text.dart';
import '../../widgets/nav_back_button.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(leading: const NavBackButton(), title: const Text('Cài đặt')),
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
                                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                                      backgroundImage: m.logoUrl != null ? NetworkImage(m.logoUrl!) : null,
                                      child: m.logoUrl == null ? Icon(Icons.storefront, color: theme.colorScheme.primary) : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(m.name, style: theme.textTheme.titleMedium),
                                          Text('Trạng thái: ${m.status} · Hoa hồng: ${m.commissionRate}%',
                                              style: theme.textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('Đơn tối thiểu: ${formatVnd(m.minOrderAmount)} · TG chuẩn bị: ${m.avgPrepMinutes} phút',
                                    style: theme.textTheme.bodySmall),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => context.push('/settings/profile', extra: m),
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (branches) => Column(
                    children: branches
                        .map((b) => Card(
                              elevation: 0,
                              color: theme.colorScheme.surfaceContainerLow,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SwitchListTile(
                                      title: Text(b.name),
                                      subtitle: Text(b.fullLine.isEmpty ? '${b.line1}, ${b.province}' : b.fullLine),
                                      value: b.isOpen,
                                      onChanged: (val) async {
                                        try {
                                          await MerchantRepository().toggleBranchOpen(b.id, val);
                                          ref.invalidate(_branchesProvider);
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                                          }
                                        }
                                      },
                                      secondary: Icon(
                                        b.isOpen ? Icons.storefront : Icons.storefront_outlined,
                                        color: b.isOpen ? Colors.green : Colors.grey,
                                      ),
                                    ),
                                    SwitchListTile(
                                      title: const Text('Tự động nhận đơn'),
                                      subtitle: const Text(
                                          'Bật: vẫn hiện màn nhận đơn, đếm ngược bằng màu trên thanh trượt — hết giờ hệ thống tự nhận hộ.\n'
                                          'Tắt: có ít phút để tự xác nhận thủ công — hết giờ đơn tự huỷ và chi nhánh tự đóng cửa.\n'
                                          '(Số phút cụ thể do HOFA cấu hình chung cho toàn hệ thống.)'),
                                      value: b.autoAcceptOrders,
                                      onChanged: (val) async {
                                        try {
                                          await MerchantRepository().setAutoAcceptOrders(b.id, val);
                                          ref.invalidate(_branchesProvider);
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                                          }
                                        }
                                      },
                                      secondary: const Icon(Icons.bolt_outlined),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => context.push('/settings/branches/${b.id}', extra: b),
                                            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                                            label: const Text('Sửa địa chỉ'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () => context.push('/settings/branches/${b.id}/hours', extra: b.name),
                                            icon: const Icon(Icons.schedule_outlined, size: 18),
                                            label: const Text('Giờ mở cửa'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tắt công tắc khi hết hàng hoặc nghỉ đột xuất — cửa hàng sẽ tạm ngừng nhận đơn mới.',
                  style: TextStyle(color: Colors.grey),
                ),
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
                    subtitle: const Text('Xem và gỡ các thiết bị đang nhận thông báo'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
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
                const AppVersionText(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
