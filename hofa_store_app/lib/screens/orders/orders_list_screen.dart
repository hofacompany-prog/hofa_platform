import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/nav_back_button.dart';

final _selectedStatusProvider = StateProvider.autoDispose<String?>((ref) => null);

final _ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  final status = ref.watch(_selectedStatusProvider);
  return OrderRepository().listForMerchant(merchant.id, status: status);
});

/// order_id của mọi thông báo danh mục "Đơn hàng" CHƯA ĐỌC — dùng để chấm đỏ đúng dòng đơn
/// tương ứng trong danh sách, không phải cờ riêng trên bảng orders (không có cột nào như vậy).
final _unreadOrderIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final notifications = await ref.watch(notificationRepoProvider).list(category: 'order', limit: 100);
  return notifications
      .where((n) => !n.isRead)
      .map((n) => n.data['order_id'] as String?)
      .whereType<String>()
      .toSet();
});

class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_ordersProvider);
    final selectedStatus = ref.watch(_selectedStatusProvider);
    final unreadOrderIds = ref.watch(_unreadOrderIdsProvider).valueOrNull ?? const <String>{};

    final filters = <String?, String>{
      null: 'Tất cả',
      'placed': 'Đơn mới',
      'confirmed': 'Đã xác nhận',
      'preparing': 'Đang chuẩn bị',
      'ready_for_pickup': 'Chờ lấy hàng',
      'delivering': 'Đang giao',
      'completed': 'Hoàn tất',
      'cancelled': 'Đã huỷ',
    };

    return Scaffold(
      appBar: AppBar(leading: const NavBackButton(), title: const Text('Đơn hàng')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: filters.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: selectedStatus == e.key,
                          onSelected: (_) => ref.read(_selectedStatusProvider.notifier).state = e.key,
                        ),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi tải đơn hàng: $e')),
              data: (orders) {
                if (orders.isEmpty) {
                  return const Center(child: Text('Không có đơn nào'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_ordersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      final isUnread = unreadOrderIds.contains(o.id);
                      return Card(
                        child: ListTile(
                          onTap: () async {
                            if (isUnread) {
                              final notifications = await ref.read(notificationRepoProvider).list(category: 'order', limit: 100);
                              for (final n in notifications) {
                                if (!n.isRead && n.data['order_id'] == o.id) {
                                  ref.read(notificationRepoProvider).markRead(n.id).catchError((_) {});
                                }
                              }
                              ref.invalidate(_unreadOrderIdsProvider);
                              ref.invalidate(unreadOrderCountProvider);
                            }
                            if (context.mounted) context.push('/orders/${o.id}');
                          },
                          leading: isUnread
                              ? const CircleAvatar(radius: 5, backgroundColor: Colors.red)
                              : const SizedBox(width: 10),
                          title: Text(
                            '${o.orderCode} — ${o.shipRecipientName}',
                            style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
                          ),
                          subtitle: Text('${formatVnd(o.totalAmount)} · ${formatDateTime(o.createdAt)}'),
                          trailing: Chip(label: Text(orderStatusLabels[o.status] ?? o.status)),
                        ),
                      );
                    },
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
