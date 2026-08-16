import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/format.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/branch_hours.dart' show weekdayLabels;
import '../../models/finance_summary.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/nav_back_button.dart';
import '../../widgets/stat_card.dart';

final _financePeriodProvider = StateProvider.autoDispose<String>(
  (ref) => 'today',
);

final _financeOrdersProvider = FutureProvider.autoDispose<List<Order>>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  final summary = await ref.watch(
    financeSummaryProvider(ref.watch(_financePeriodProvider)).future,
  );
  if (summary == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  // payoutOnly: true — chỉ đơn ĐÃ GIAO mới tính là giao dịch thật (khớp cách tính mới của
  // financeSummaryProvider, xem GET /merchants/:id/orders?payout_only=true).
  return OrderRepository().listForMerchant(
    merchant.id,
    from: fmt.format(summary.from),
    to: fmt.format(summary.to),
    payoutOnly: true,
  );
});

/// Màn "Tài chính" — doanh thu/thu nhập thật của cửa hàng, tách 3 tab giống app merchant các
/// nền tảng giao đồ ăn khác: Tóm tắt (số liệu), Giao dịch (từng đơn), Số tiền thu về. Cả 3 tab
/// CHỈ tính đơn đã ở trạng thái "Đã giao" (đọc từ sổ cái merchant_wallet_transactions, xem
/// hofa-db/64_merchant_wallet_ledger.sql) — đơn đang chạy (đặt/chuẩn bị/đang giao) dù chưa huỷ
/// không được tính là đã có tiền. Tab thứ 3 đọc số dư ví thật (khác netIncome theo kỳ ở 2 tab
/// đầu) và cho rút tiền — mirror luồng "Rút tiền" của tài xế, xem
/// hofa-db/65_merchant_wallet_withdrawals.sql.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(_financePeriodProvider);
    final summaryAsync = ref.watch(financeSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Tài chính'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tóm tắt'),
            Tab(text: 'Giao dịch'),
            Tab(text: 'Số tiền thu về'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: financePeriodLabels.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: period == e.key,
                        onSelected: (_) =>
                            ref.read(_financePeriodProvider.notifier).state =
                                e.key,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SummaryTab(summaryAsync: summaryAsync),
                _TransactionsTab(summaryAsync: summaryAsync),
                const _PayoutTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final AsyncValue<FinanceSummary?> summaryAsync;
  const _SummaryTab({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (summary) {
        if (summary == null)
          return const Center(child: Text('Chưa có dữ liệu'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Doanh thu ròng',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+${formatVnd(summary.revenue)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thu nhập',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+${formatVnd(summary.netIncome)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Chi tiết',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _row(
                      context,
                      'Doanh thu ròng (${summary.orderCount} đơn)',
                      formatVnd(summary.revenue),
                    ),
                    _row(
                      context,
                      'Khấu trừ hoa hồng (${summary.commissionRate}%)',
                      '-${formatVnd(summary.commissionAmount)}',
                    ),
                    _row(
                      context,
                      'Thuế GTGT (${summary.vatRate}%)',
                      '-${formatVnd(summary.vatAmount)}',
                    ),
                    _row(
                      context,
                      'Thuế TNCN (${summary.pitRate}%)',
                      '-${formatVnd(summary.pitAmount)}',
                    ),
                    const Divider(height: 1),
                    _row(
                      context,
                      'Thu nhập ròng',
                      '+${formatVnd(summary.netIncome)}',
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? style : theme.textTheme.bodyMedium,
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final AsyncValue<FinanceSummary?> summaryAsync;
  const _TransactionsTab({required this.summaryAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(_financeOrdersProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (orders) {
        if (orders.isEmpty) {
          return const Center(
            child: Text('Chưa có giao dịch nào trong khoảng thời gian này'),
          );
        }
        final now = DateTime.now();
        String dateHeader(DateTime d) {
          // Không dùng DateFormat('EEEE', 'vi') — cần initializeDateFormatting() trước, app
          // này chưa gọi; dùng lại weekdayLabels đã có sẵn cho tên thứ tiếng Việt.
          final label =
              '${weekdayLabels[d.weekday % 7]}, ${DateFormat('d/M/yyyy').format(d)}';
          final isToday =
              d.year == now.year && d.month == now.month && d.day == now.day;
          final yesterday = now.subtract(const Duration(days: 1));
          final isYesterday =
              d.year == yesterday.year &&
              d.month == yesterday.month &&
              d.day == yesterday.day;
          if (isToday) return '$label (Hôm nay)';
          if (isYesterday) return '$label (Hôm qua)';
          return label;
        }

        // Nhóm/hiện theo ngày GIAO (deliveredAt) — ngày tiền thực sự được tính, không phải ngày
        // đặt (createdAt) — khớp payout_only=true đã lọc ở _financeOrdersProvider. Luôn khác
        // null ở đây (đã lọc payout_only), fallback createdAt chỉ để phòng dữ liệu cũ.
        final grouped = <String, List<Order>>{};
        for (final o in orders) {
          final key = DateFormat(
            'yyyy-MM-dd',
          ).format(o.deliveredAt ?? o.createdAt);
          (grouped[key] ??= []).add(o);
        }
        final sortedKeys = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final key in sortedKeys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  dateHeader(
                    grouped[key]!.first.deliveredAt ??
                        grouped[key]!.first.createdAt,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              ...grouped[key]!.map(
                (o) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(
                      Icons.restaurant_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    'Thanh toán ${o.orderCode}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Giao đơn hàng'),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatVnd(o.totalAmount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        DateFormat(
                          'HH:mm',
                        ).format(o.deliveredAt ?? o.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StatCard(
                label: 'Tổng giao dịch',
                value: '${orders.length}',
                icon: Icons.receipt_long_outlined,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PayoutTab extends ConsumerWidget {
  const _PayoutTab();

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
    int balance,
  ) async {
    final amountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rút tiền'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Số dư khả dụng: ${formatVnd(balance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [VndInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Số tiền muốn rút (đ)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    final amount = VndInputFormatter.parse(amountCtrl.text);
    if (ok != true || amount == null || amount <= 0 || !context.mounted) return;

    try {
      await MerchantRepository().createWalletWithdrawal(merchantId, amount);
      ref.invalidate(merchantWalletBalanceProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã gửi yêu cầu rút tiền — HOFA sẽ chuyển khoản sớm.',
            ),
          ),
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
    final merchantAsync = ref.watch(myMerchantProvider);
    final balanceAsync = ref.watch(merchantWalletBalanceProvider);

    return balanceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (balance) {
        if (balance == null)
          return const Center(child: Text('Chưa có dữ liệu'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Số dư',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatVnd(balance),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: balance <= 0
                  ? null
                  : () {
                      final merchant = merchantAsync.valueOrNull;
                      if (merchant == null) return;
                      _withdraw(context, ref, merchant.id, balance);
                    },
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('Rút tiền'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Số dư là thu nhập thật đã cộng vào ví sau khi đơn được giao và trừ hoa '
                      'hồng (xem tab Tóm tắt để biết chi tiết khấu trừ). Cần cập nhật đủ thông '
                      'tin ngân hàng ở Cài đặt → Hồ sơ cửa hàng trước khi rút.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
