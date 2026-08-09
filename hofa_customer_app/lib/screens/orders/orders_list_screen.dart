import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/app_providers.dart';

Color orderStatusColor(String status, ColorScheme scheme) => switch (status) {
      'completed' || 'delivered' => Colors.green,
      'cancelled' || 'refunded' => scheme.error,
      'pending_payment' => Colors.orange,
      _ => scheme.primary,
    };

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      final status = ref.read(orderStatusFilterProvider);
      ref.read(myOrdersPagedProvider(status).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusFilter = ref.watch(orderStatusFilterProvider);
    final ordersState = ref.watch(myOrdersPagedProvider(statusFilter));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn hàng của tôi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myOrdersPagedProvider(statusFilter)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: ordersState.isInitialLoading
                ? const Center(child: CircularProgressIndicator())
                : ordersState.error != null && ordersState.items.isEmpty
                    ? Center(child: Text('Lỗi: ${ordersState.error}'))
                    : ordersState.items.isEmpty
                        ? const Center(child: Text('Bạn chưa có đơn hàng nào'))
                        : ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: ordersState.items.length + (ordersState.hasMore ? 1 : 0),
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              if (i == ordersState.items.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              final o = ordersState.items[i];
                              final color = orderStatusColor(o.status, theme.colorScheme);
                              return Card(
                                elevation: 0,
                                color: theme.colorScheme.surfaceContainerLow,
                                child: ListTile(
                                  onTap: () => context.push('/orders/${o.id}'),
                                  title: Text(o.orderCode, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text(formatDateTime(o.createdAt)),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(formatVnd(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Chip(
                                        label: Text(orderStatusLabels[o.status] ?? o.status, style: const TextStyle(fontSize: 11)),
                                        backgroundColor: color.withValues(alpha: 0.12),
                                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
