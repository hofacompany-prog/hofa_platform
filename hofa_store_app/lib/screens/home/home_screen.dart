import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/nav_destinations.dart';
import '../../models/branch.dart';
import '../../models/finance_summary.dart';
import '../../models/merchant_today_stats.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../widgets/notification_bell.dart';

final _homeBranchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return MerchantRepository().branches(merchant.id);
});

/// Trang chủ — tổng quan nhanh (đơn đang chuẩn bị, thu nhập hôm nay) + lối tắt tới mọi mục
/// quản lý, thay cho việc phải mở app luôn vào thẳng màn Sản phẩm như trước. Route đầu tiên
/// của ShellRoute (xem router.dart) và cũng là tab đầu trong bottom bar/NavigationRail.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _toggleOpen(WidgetRef ref, Branch branch) async {
    try {
      await MerchantRepository().toggleBranchOpen(branch.id, !branch.isOpen);
      ref.invalidate(_homeBranchesProvider);
    } catch (_) {
      // Lỗi mạng tạm thời — người dùng vẫn có thể đổi lại ở màn Cài đặt, không chặn Trang chủ.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final merchantAsync = ref.watch(myMerchantProvider);
    final statsAsync = ref.watch(merchantTodayStatsProvider);
    final todayFinanceAsync = ref.watch(financeSummaryProvider('today'));
    final branches = ref.watch(_homeBranchesProvider).valueOrNull ?? const <Branch>[];
    final mainBranch = branches.isEmpty
        ? null
        : branches.firstWhere((b) => b.isMain, orElse: () => branches.first);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myMerchantProvider);
            ref.invalidate(merchantTodayStatsProvider);
            ref.invalidate(financeSummaryProvider('today'));
            ref.invalidate(_homeBranchesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_outlined, color: theme.colorScheme.outline, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      merchantAsync.when(
                        data: (m) => m == null
                            ? ''
                            : (mainBranch != null ? '${m.name} - ${mainBranch.name}' : m.name),
                        loading: () => '',
                        error: (_, _) => '',
                      ),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const NotificationBell(),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Hiệu suất bán hàng',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _PreparingCard(
                        branch: mainBranch,
                        stats: statsAsync.valueOrNull,
                        onToggleOpen: mainBranch == null ? null : () => _toggleOpen(ref, mainBranch),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _RevenueCard(summary: todayFinanceAsync.valueOrNull)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Quản lý cửa hàng',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: [
                  ...kNavDestinations
                      .where((d) => d.path != '/home')
                      .map((d) => _ShortcutTile(icon: d.selected, label: d.label, path: d.path)),
                  // Danh mục không còn nằm trong thanh điều hướng chính (nhường chỗ cho Tài
                  // chính) nhưng vẫn cần dùng được — giữ lại làm lối tắt ở đây, giống Thiết bị.
                  const _ShortcutTile(
                    icon: Icons.category_outlined,
                    label: 'Danh mục',
                    path: '/categories',
                  ),
                  const _ShortcutTile(
                    icon: Icons.devices_other_outlined,
                    label: 'Thiết bị',
                    path: '/settings/devices',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreparingCard extends StatelessWidget {
  final Branch? branch;
  final MerchantTodayStats? stats;
  final VoidCallback? onToggleOpen;

  const _PreparingCard({required this.branch, required this.stats, required this.onToggleOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = branch?.isOpen ?? true;
    // Tạm đóng: cửa hàng bị ẩn khỏi kết quả tìm kiếm/xám đi ở app khách, khách vẫn xem được
    // sản phẩm nhưng không đặt hàng được (xem GET /merchants has_open_branch và POST /orders
    // chặn tạo đơn khi chi nhánh đóng) — nền đỏ ở đây để chủ cửa hàng nhận ra ngay tình trạng
    // này thay vì lỡ quên bật lại.
    return Card(
      elevation: 0,
      color: isOpen ? theme.colorScheme.primary : theme.colorScheme.error,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isOpen ? 'Đang mở cửa' : 'Tạm đóng cửa',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: isOpen,
                  onChanged: onToggleOpen == null ? null : (_) => onToggleOpen!(),
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.white.withValues(alpha: 0.4),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.4),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${stats?.preparingCount ?? 0}',
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Đang chuẩn bị',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final FinanceSummary? summary;
  const _RevenueCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Thu nhập ròng (đã trừ hoa hồng + thuế) — bấm vào xem chi tiết ở màn Tài chính.
        onTap: () => context.push('/finance'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.12),
                    child: Icon(Icons.trending_up, size: 18, color: theme.colorScheme.secondary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thu nhập hôm nay',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
                ],
              ),
              const Spacer(),
              Text(
                formatVnd(summary?.netIncome ?? 0),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${summary?.orderCount ?? 0} đơn hàng',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;

  const _ShortcutTile({required this.icon, required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(path),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
