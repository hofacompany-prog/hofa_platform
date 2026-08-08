import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/nav_back_button.dart';

/// Gom 12 trạng thái đơn (order_status, xem 01_schema.sql) lại còn 5 nhóm dễ hiểu cho cửa
/// hàng — mỗi trạng thái thật thuộc đúng 1 nhóm. "Sắp tới" = đơn mới chưa xác nhận, "Đang
/// chuẩn bị" = đã nhận đang làm, "Đã làm xong" = đã sẵn sàng, từ lúc chờ tài xế tới lúc đang
/// giao (không còn là việc của bếp nữa), "Đã hoàn tất"/"Đã hủy" giữ nguyên ý nghĩa gốc.
const _statusGroups = <String, List<String>>{
  'Đang chuẩn bị': ['confirmed', 'preparing'],
  'Đã làm xong': ['ready_for_pickup', 'assigned', 'picked_up', 'delivering', 'delivered'],
  'Sắp tới': ['pending_payment', 'placed'],
  'Đã hoàn tất': ['completed'],
  'Đã hủy': ['cancelled', 'refunded'],
};

final _selectedGroupProvider = StateProvider.autoDispose<String>((ref) => _statusGroups.keys.first);

final _ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return OrderRepository().listForMerchant(merchant.id);
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
    final selectedGroup = ref.watch(_selectedGroupProvider);
    final unreadOrderIds = ref.watch(_unreadOrderIdsProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(leading: const NavBackButton(), title: const Text('Đơn hàng')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: _statusGroups.keys
                  .map((name) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(name),
                          selected: selectedGroup == name,
                          onSelected: (_) => ref.read(_selectedGroupProvider.notifier).state = name,
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
              data: (allOrders) {
                final statuses = _statusGroups[selectedGroup]!;
                final orders = allOrders.where((o) => statuses.contains(o.status)).toList();
                if (orders.isEmpty) {
                  return const Center(child: Text('Không có đơn nào'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_ordersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                            o.orderCode,
                            style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
                          ),
                          subtitle: Text('${formatVnd(o.totalAmount)} · ${formatDateTime(o.createdAt)}'),
                          trailing: (o.lateMinutes ?? 0) > 0
                              ? Chip(
                                  label: Text('${orderStatusLabels[o.status] ?? o.status} · Trễ ${o.lateMinutes}p'),
                                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                                )
                              : Chip(label: Text(orderStatusLabels[o.status] ?? o.status)),
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
