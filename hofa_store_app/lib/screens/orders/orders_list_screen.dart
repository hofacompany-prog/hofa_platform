import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/date_range_preset.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/nav_back_button.dart';
import '../../widgets/rolling_countdown.dart';
import '../../widgets/stat_card.dart';

/// Gom 12 trạng thái đơn (order_status, xem 01_schema.sql) lại còn 5 nhóm dễ hiểu cho cửa
/// hàng — mỗi trạng thái thật thuộc đúng 1 nhóm. "Sắp tới" = đơn mới chưa xác nhận, "Đang
/// chuẩn bị" = đã nhận đang làm, "Đã làm xong" = đã sẵn sàng, từ lúc chờ tài xế tới lúc đang
/// giao (không còn là việc của bếp nữa), "Đã hoàn tất"/"Đã hủy" giữ nguyên ý nghĩa gốc.
const _statusGroups = <String, List<String>>{
  'Đang chuẩn bị': ['confirmed', 'preparing'],
  'Đã làm xong': [
    'ready_for_pickup',
    'assigned',
    'picked_up',
    'delivering',
    'delivered',
  ],
  'Sắp tới': ['pending_payment', 'placed'],
  'Đã hoàn tất': ['completed'],
  'Đã hủy': ['cancelled', 'refunded'],
};

/// Thứ tự tab hiển thị — "Sắp tới" lên đầu (đơn mới chưa xác nhận cần thấy ngay), tab MẶC ĐỊNH
/// lúc mở màn vẫn là "Đang chuẩn bị" (đặt riêng ở _selectedGroupProvider, không suy từ .first
/// nữa) — bếp đang làm gì mới là việc cần thấy ngay khi mở màn, dù không còn đứng đầu danh sách.
const _tabOrder = [
  'Sắp tới',
  'Đang chuẩn bị',
  'Đã làm xong',
  'Đã hoàn tất',
  'Đã hủy',
];

final _selectedGroupProvider = StateProvider.autoDispose<String>(
  (ref) => 'Đang chuẩn bị',
);

/// Ô lọc khoảng thời gian đã dời qua màn Tài chính (finance_screen.dart) — màn Đơn hàng là
/// worklist vận hành (đang chuẩn bị/sắp tới hôm nay), không cần chọn khoảng ngày, luôn cố định
/// "Hôm nay" để không phải tải toàn bộ lịch sử đơn không giới hạn thời gian.
final _ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  final (from, to) = DateRangePreset.today.toRange();
  return OrderRepository().listForMerchant(merchant.id, from: from, to: to);
});

/// order_id của mọi thông báo danh mục "Đơn hàng" CHƯA ĐỌC — dùng để chấm đỏ đúng dòng đơn
/// tương ứng trong danh sách, không phải cờ riêng trên bảng orders (không có cột nào như vậy).
final _unreadOrderIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final notifications = await ref
      .watch(notificationRepoProvider)
      .list(category: 'order', limit: 100);
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
    final unreadOrderIds =
        ref.watch(_unreadOrderIdsProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Đơn hàng'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: _tabOrder
                  .map(
                    (name) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: selectedGroup == name,
                        onSelected: (_) =>
                            ref.read(_selectedGroupProvider.notifier).state =
                                name,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi tải đơn hàng: $e')),
              data: (allOrders) {
                final orders = allOrders
                    .where(
                      (o) => _statusGroups[selectedGroup]!.contains(o.status),
                    )
                    .toList();
                if (orders.isEmpty) {
                  return const Center(child: Text('Không có đơn nào'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_ordersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: orders.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == orders.length) {
                        return StatCard(
                          label: 'Tổng đơn (đang lọc)',
                          value: '${orders.length}',
                          icon: Icons.receipt_long_outlined,
                        );
                      }
                      final o = orders[i];
                      final isUnread = unreadOrderIds.contains(o.id);

                      Future<void> openOrder() async {
                        if (isUnread) {
                          final notifications = await ref
                              .read(notificationRepoProvider)
                              .list(category: 'order', limit: 100);
                          for (final n in notifications) {
                            if (!n.isRead && n.data['order_id'] == o.id) {
                              ref
                                  .read(notificationRepoProvider)
                                  .markRead(n.id)
                                  .catchError((_) {});
                            }
                          }
                          ref.invalidate(_unreadOrderIdsProvider);
                          ref.invalidate(unreadOrderCountProvider);
                        }
                        if (context.mounted) context.push('/orders/${o.id}');
                      }

                      // Đang chuẩn bị: thay chip trạng thái bằng đồng hồ đếm ngược + nút "Đã làm
                      // xong" hệt màn chi tiết đơn (RollingCountdown dùng chung), thay vì chỉ hiện
                      // 1 chip tĩnh — cửa hàng thấy ngay đơn nào sắp trễ mà không cần bấm vào xem.
                      if (o.status == 'confirmed' || o.status == 'preparing') {
                        return _PreparingOrderCard(
                          order: o,
                          isUnread: isUnread,
                          onTap: openOrder,
                        );
                      }

                      return Card(
                        child: ListTile(
                          onTap: openOrder,
                          leading: isUnread
                              ? const CircleAvatar(
                                  radius: 5,
                                  backgroundColor: Colors.red,
                                )
                              : const SizedBox(width: 10),
                          title: Text(
                            o.orderCode,
                            style: TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${formatVnd(o.totalAmount)} · ${formatDateTime(o.createdAt)}',
                          ),
                          trailing: (o.lateMinutes ?? 0) > 0
                              ? Chip(
                                  label: Text(
                                    '${orderStatusLabels[o.status] ?? o.status} · Trễ ${o.lateMinutes}p',
                                  ),
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.errorContainer,
                                  labelStyle: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                )
                              : Chip(
                                  label: Text(
                                    orderStatusLabels[o.status] ?? o.status,
                                  ),
                                ),
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

/// Dòng đơn "Đang chuẩn bị" — thay chip trạng thái tĩnh bằng RollingCountdown (đúng đồng hồ dùng
/// ở màn chi tiết đơn: đếm lùi thật, đóng băng đỏ "Đơn hàng đang bị trễ" khi hết giờ) + nút "Đã
/// làm xong" bấm thẳng từ danh sách, không cần mở chi tiết đơn trước.
class _PreparingOrderCard extends ConsumerStatefulWidget {
  final Order order;
  final bool isUnread;
  final Future<void> Function() onTap;
  const _PreparingOrderCard({
    required this.order,
    required this.isUnread,
    required this.onTap,
  });

  @override
  ConsumerState<_PreparingOrderCard> createState() =>
      _PreparingOrderCardState();
}

class _PreparingOrderCardState extends ConsumerState<_PreparingOrderCard> {
  bool _updating = false;

  Future<void> _markDone() async {
    setState(() => _updating = true);
    try {
      final o = widget.order;
      if (o.status == 'confirmed') {
        await OrderRepository().updateStatus(o.id, 'preparing');
      }
      await OrderRepository().updateStatus(o.id, 'ready_for_pickup');
      ref.invalidate(_ordersProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Card(
      child: Column(
        children: [
          ListTile(
            onTap: widget.onTap,
            leading: widget.isUnread
                ? const CircleAvatar(radius: 5, backgroundColor: Colors.red)
                : const SizedBox(width: 10),
            title: Text(
              o.orderCode,
              style: TextStyle(
                fontWeight: widget.isUnread
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              '${formatVnd(o.totalAmount)} · ${formatDateTime(o.createdAt)}',
            ),
          ),
          if (o.confirmedAt != null && o.estimatedPrepMinutes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: RollingCountdown(
                      deadline: o.confirmedAt!.add(
                        Duration(minutes: o.estimatedPrepMinutes!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _updating ? null : _markDone,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Đã làm xong'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
