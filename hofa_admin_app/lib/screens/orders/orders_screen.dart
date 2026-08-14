import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

final _yyyyMMdd = DateFormat('yyyy-MM-dd');

Color statusColor(String status, ColorScheme scheme) => switch (status) {
  'completed' || 'delivered' => Colors.green,
  'cancelled' || 'refunded' => scheme.error,
  'pending_payment' => Colors.orange,
  _ => scheme.primary,
};

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  /// Ngoại lệ chỉ admin có — app khách/cửa hàng bắt buộc chọn 1 trong 4 khoảng nhanh (Hôm nay/
  /// Hôm qua/Tuần qua/Tháng qua), còn admin chọn khoảng ngày tuỳ ý để vẫn xem được TẤT CẢ đơn
  /// (để trống from/to) hoặc thu hẹp theo đúng khoảng cần tra.
  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final from = ref.read(orderFromDateProvider);
    final to = ref.read(orderToDateProvider);
    final initial = from != null && to != null
        ? DateTimeRange(start: DateTime.parse(from), end: DateTime.parse(to))
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: initial,
      helpText: 'Chọn khoảng thời gian',
    );
    if (picked == null) return;
    ref.read(orderFromDateProvider.notifier).state = _yyyyMMdd.format(
      picked.start,
    );
    ref.read(orderToDateProvider.notifier).state = _yyyyMMdd.format(picked.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    final statusFilter = ref.watch(orderStatusFilterProvider);
    final fromDate = ref.watch(orderFromDateProvider);
    final toDate = ref.watch(orderToDateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn hàng'),
        actions: [
          if (fromDate != null && toDate != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                label: Text('$fromDate → $toDate'),
                onDeleted: () {
                  ref.read(orderFromDateProvider.notifier).state = null;
                  ref.read(orderToDateProvider.notifier).state = null;
                },
                onPressed: () => _pickDateRange(context, ref),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: () => _pickDateRange(context, ref),
                icon: const Icon(Icons.date_range_outlined),
                label: const Text('Chọn khoảng thời gian'),
              ),
            ),
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ordersProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: statusFilter == null,
                    onSelected: (_) =>
                        ref.read(orderStatusFilterProvider.notifier).state =
                            null,
                  ),
                ),
                ...orderStatusLabels.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: statusFilter == e.key,
                      onSelected: (_) =>
                          ref.read(orderStatusFilterProvider.notifier).state =
                              e.key,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (orders) {
                if (orders.isEmpty)
                  return const Center(child: Text('Không có đơn nào'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: orders.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == orders.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatCard(
                          label: 'Tổng đơn (đang lọc)',
                          value: '${orders.length}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      );
                    }
                    final o = orders[i];
                    final color = statusColor(o.status, theme.colorScheme);
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: InkWell(
                        onTap: () => context.go('/orders/${o.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${o.orderCode} · ${o.merchantName ?? ""}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${o.customerName ?? o.shipRecipientName} — ${formatDateTime(o.createdAt)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    formatVnd(o.totalAmount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      orderStatusLabels[o.status] ?? o.status,
                                    ),
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    side: BorderSide(
                                      color: color.withValues(alpha: 0.4),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
