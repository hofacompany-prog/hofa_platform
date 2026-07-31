import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng quan'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(statsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Không tải được số liệu: $e')),
        data: (s) => LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1200
                ? 4
                : constraints.maxWidth > 800
                    ? 3
                    : 2;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.6,
                    children: [
                      StatCard(
                        label: 'Đơn hôm nay',
                        value: '${s.orders.today}',
                        sub: 'Tổng ${s.orders.total} đơn · ${s.orders.inProgress} đang chạy',
                        icon: Icons.receipt_long,
                      ),
                      StatCard(
                        label: 'Doanh thu đã giao',
                        value: formatVnd(s.revenue.gross),
                        sub: 'HOFA thu hoa hồng ${formatVnd(s.revenue.commission)}',
                        icon: Icons.payments,
                        accent: Colors.teal,
                      ),
                      StatCard(
                        label: 'Cửa hàng',
                        value: '${s.merchants.active}',
                        sub: '${s.merchants.pendingReview} chờ duyệt · ${s.merchants.paused} tạm dừng',
                        icon: Icons.storefront,
                        accent: Colors.indigo,
                      ),
                      StatCard(
                        label: 'Người dùng',
                        value: '${s.users.total}',
                        sub: '${s.users.customers} khách · ${s.users.drivers} tài xế',
                        icon: Icons.people,
                        accent: Colors.orange,
                      ),
                    ],
                  ),
                  if (s.merchants.pendingReview > 0) ...[
                    const SizedBox(height: 24),
                    Card(
                      color: theme.colorScheme.tertiaryContainer,
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.pending_actions),
                        title: Text('${s.merchants.pendingReview} cửa hàng đang chờ bạn duyệt'),
                        trailing: FilledButton(
                          onPressed: () => context.go('/merchants'),
                          child: const Text('Xem ngay'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('Đơn hàng gần đây', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: s.recentOrders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Chưa có đơn hàng nào')),
                          )
                        : Column(
                            children: s.recentOrders
                                .map((o) => ListTile(
                                      onTap: () => context.go('/orders/${o.id}'),
                                      title: Text('${o.orderCode} · ${o.merchantName}'),
                                      subtitle: Text('${o.customerName} — ${formatDateTime(o.createdAt)}'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(formatVnd(o.totalAmount),
                                              style: const TextStyle(fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 12),
                                          Chip(
                                            label: Text(orderStatusLabels[o.status] ?? o.status),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
