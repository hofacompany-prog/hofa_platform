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
import '../../repositories/order_repository.dart';
import '../../widgets/branch_break_dialogs.dart';
import '../../widgets/notification_bell.dart';

final _homeBranchesProvider = FutureProvider.autoDispose<List<Branch>>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return MerchantRepository().branches(merchant.id);
});

/// Trang chủ — tổng quan nhanh (đơn đang chuẩn bị, thu nhập hôm nay) + lối tắt tới mọi mục
/// quản lý, thay cho việc phải mở app luôn vào thẳng màn Sản phẩm như trước. Route đầu tiên
/// của ShellRoute (xem router.dart) và cũng là tab đầu trong bottom bar/NavigationRail.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _toggleOpen(
    WidgetRef ref,
    Branch branch,
    bool isOpen, {
    DateTime? breakUntil,
  }) async {
    try {
      await MerchantRepository().toggleBranchOpen(
        branch.id,
        isOpen,
        breakUntil: breakUntil,
      );
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
    final branches =
        ref.watch(_homeBranchesProvider).valueOrNull ?? const <Branch>[];
    final myPermissions = ref.watch(myPermissionsProvider).valueOrNull;
    final preparingCount = statsAsync.valueOrNull?.preparingCount ?? 0;
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
                  Icon(
                    Icons.location_on_outlined,
                    color: theme.colorScheme.outline,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      merchantAsync.when(
                        data: (m) => m == null
                            ? ''
                            : (mainBranch != null
                                  ? '${m.name} - ${mainBranch.name}'
                                  : m.name),
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
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                        onToggle: mainBranch == null
                            ? null
                            : (isOpen, {breakUntil}) => _toggleOpen(
                                ref,
                                mainBranch,
                                isOpen,
                                breakUntil: breakUntil,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RevenueCard(
                        summary: todayFinanceAsync.valueOrNull,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Quản lý cửa hàng',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                      .where(
                        (d) =>
                            d.permission == null ||
                            hasPermission(myPermissions, d.permission!),
                      )
                      .map(
                        (d) => _ShortcutTile(
                          icon: d.selected,
                          label: d.label,
                          path: d.path,
                          badgeCount: d.path == '/orders' ? preparingCount : 0,
                        ),
                      ),
                  // Danh mục và Kho hàng không còn nằm trong thanh điều hướng chính (đỡ chật,
                  // nhường chỗ cho Tài chính) nhưng vẫn cần dùng được — giữ lại làm lối tắt ở
                  // đây, giống Thiết bị. Ẩn với nhân viên không có quyền tương ứng, giống các
                  // lối tắt khác ở trên.
                  if (hasPermission(myPermissions, 'products.view'))
                    const _ShortcutTile(
                      icon: Icons.category_outlined,
                      label: 'Danh mục',
                      path: '/categories',
                    ),
                  // Cửa hàng mua hộ không có tồn kho thật (tài xế tự đi mua theo yêu cầu) — ẩn
                  // lối tắt Kho hàng, xem hofa-db/77_buy_on_behalf_unlimited_stock.sql.
                  if (hasPermission(myPermissions, 'inventory.manage') &&
                      merchantAsync.valueOrNull?.merchantType !=
                          'buy_on_behalf')
                    const _ShortcutTile(
                      icon: Icons.inventory_2_outlined,
                      label: 'Kho hàng',
                      path: '/inventory',
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

class _PreparingCard extends StatefulWidget {
  final Branch? branch;
  final MerchantTodayStats? stats;
  final Future<void> Function(bool isOpen, {DateTime? breakUntil})? onToggle;

  const _PreparingCard({
    required this.branch,
    required this.stats,
    required this.onToggle,
  });

  @override
  State<_PreparingCard> createState() => _PreparingCardState();
}

class _PreparingCardState extends State<_PreparingCard> {
  bool _checking = false;

  /// Bấm vào thẻ (không phải công tắc mở/đóng cửa, tự bắt gesture riêng nên không đụng
  /// nhau) — đúng 1 đơn đang chuẩn bị thì mở thẳng đơn đó, nhiều hơn 1 thì mở danh sách đơn
  /// hàng (mặc định mở sẵn ở tab "Đang chuẩn bị", xem orders_list_screen.dart), không có đơn
  /// nào thì không làm gì.
  Future<void> _onTap() async {
    final merchantId = widget.branch?.merchantId;
    if (merchantId == null ||
        (widget.stats?.preparingCount ?? 0) == 0 ||
        _checking) {
      return;
    }
    setState(() => _checking = true);
    try {
      final orders = await OrderRepository().listForMerchant(merchantId);
      final preparing = orders
          .where((o) => o.status == 'confirmed' || o.status == 'preparing')
          .toList();
      if (!mounted || preparing.isEmpty) return;
      if (preparing.length == 1) {
        context.push('/orders/${preparing.first.id}');
      } else {
        context.push('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Tắt lúc đang mở (hoặc đang ngoài giờ) → bắt chọn thời lượng Tạm nghỉ trước khi lưu. Bật
  /// lại lúc đang Tạm nghỉ → hỏi xác nhận mở lại sớm. Không tự đổi gì nếu người dùng Huỷ.
  Future<void> _onSwitchChanged() async {
    if (widget.onToggle == null) return;
    final status = widget.branch?.status ?? 'open';
    if (status == 'on_break') {
      final ok = await confirmReopenNow(context);
      if (ok) await widget.onToggle!(true);
    } else {
      final until = await pickBreakDuration(context);
      if (until != null) await widget.onToggle!(false, breakUntil: until);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.branch?.status ?? 'open';
    final breakUntil = widget.branch?.breakUntil;
    // Đỏ = đang Tạm nghỉ (chủ cửa hàng chủ động tắt); xám = ngoài giờ hoạt động đã cấu hình
    // (branch_hours) nhưng không phải tạm nghỉ — để chủ cửa hàng phân biệt rõ 2 lý do đóng cửa.
    final cardColor = switch (status) {
      'on_break' => theme.colorScheme.error,
      'closed_hours' => Colors.grey,
      _ => theme.colorScheme.primary,
    };
    final statusText = switch (status) {
      'on_break' =>
        breakUntil != null
            ? 'Tạm nghỉ đến ${formatBreakUntil(breakUntil)}'
            : 'Tạm nghỉ',
      'closed_hours' => 'Ngoài giờ hoạt động',
      _ => 'Đang mở cửa',
    };
    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap,
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
                      statusText,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: status != 'on_break',
                    onChanged: widget.onToggle == null
                        ? null
                        : (_) => _onSwitchChanged(),
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.white.withValues(alpha: 0.4),
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const Spacer(),
              if (_checking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  '${widget.stats?.preparingCount ?? 0}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Đang chuẩn bị',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
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
                    backgroundColor: theme.colorScheme.secondary.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(
                      Icons.trending_up,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thu nhập hôm nay',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                formatVnd(summary?.netIncome ?? 0),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${summary?.orderCount ?? 0} đơn hàng',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
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
  final int badgeCount;

  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.path,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(path),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            label: Text('$badgeCount'),
            isLabelVisible: badgeCount > 0,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
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
