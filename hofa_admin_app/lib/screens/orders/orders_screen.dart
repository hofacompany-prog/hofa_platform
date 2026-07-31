import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';

Color statusColor(String status, ColorScheme scheme) => switch (status) {
      'completed' || 'delivered' => Colors.green,
      'cancelled' || 'refunded' => scheme.error,
      'pending_payment' => Colors.orange,
      _ => scheme.primary,
    };

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    final statusFilter = ref.watch(orderStatusFilterProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn hàng'),
        actions: [
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
                    onSelected: (_) => ref.read(orderStatusFilterProvider.notifier).state = null,
                  ),
                ),
                ...orderStatusLabels.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: statusFilter == e.key,
                        onSelected: (_) => ref.read(orderStatusFilterProvider.notifier).state = e.key,
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (orders) {
                if (orders.isEmpty) return const Center(child: Text('Không có đơn nào'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final o = orders[i];
                    final color = statusColor(o.status, theme.colorScheme);
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () => context.go('/orders/${o.id}'),
                        title: Text('${o.orderCode} · ${o.merchantName ?? ""}',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            '${o.customerName ?? o.shipRecipientName} — ${formatDateTime(o.createdAt)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatVnd(o.totalAmount),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            Chip(
                              label: Text(orderStatusLabels[o.status] ?? o.status),
                              backgroundColor: color.withValues(alpha: 0.12),
                              side: BorderSide(color: color.withValues(alpha: 0.4)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Icon(Icons.chevron_right),
                          ],
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
