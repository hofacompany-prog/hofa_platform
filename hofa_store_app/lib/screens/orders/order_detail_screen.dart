import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';

final _orderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _updating = false;

  Future<void> _updateStatus(String status) async {
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(widget.orderId, status);
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn?'),
        content: const Text('Đơn sẽ chuyển sang trạng thái đã huỷ, hàng đã giữ chỗ sẽ được nhả lại.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Đóng')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Huỷ đơn'),
          ),
        ],
      ),
    );
    if (ok == true) await _updateStatus('cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_orderProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết đơn hàng')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (o) {
          final next = nextMerchantStatus[o.status];
          final canCancel = ['placed', 'confirmed', 'preparing'].contains(o.status);
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(o.orderCode, style: Theme.of(context).textTheme.titleLarge),
                                Chip(label: Text(orderStatusLabels[o.status] ?? o.status)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Đặt lúc ${formatDateTime(o.createdAt)}'),
                            const Divider(height: 24),
                            Text('Người nhận: ${o.shipRecipientName}'),
                            Text('SĐT: ${o.shipRecipientPhone}'),
                            Text('Địa chỉ: ${o.shipLine1}, ${o.shipProvince}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Món hàng', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ...o.items.map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Text('${item.quantity}x '),
                                      Expanded(child: Text('${item.productName} ${item.variantName ?? ''}')),
                                      Text(formatVnd(item.lineTotal)),
                                    ],
                                  ),
                                )),
                            const Divider(),
                            _totalRow('Tạm tính', o.subtotal),
                            _totalRow('Phí giao hàng', o.deliveryFee),
                            if (o.discountAmount > 0) _totalRow('Giảm giá', -o.discountAmount),
                            _totalRow('Tổng cộng', o.totalAmount, bold: true),
                            const SizedBox(height: 4),
                            Text('Thanh toán: ${o.paymentMethod.toUpperCase()} · ${o.paymentStatus}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        if (next != null)
                          Expanded(
                            child: FilledButton(
                              onPressed: _updating ? null : () => _updateStatus(next),
                              child: Text('Chuyển sang "${orderStatusLabels[next]}"'),
                            ),
                          ),
                        if (next != null && canCancel) const SizedBox(width: 12),
                        if (canCancel)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _updating ? null : _confirmCancel,
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Huỷ đơn'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _totalRow(String label, int amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
            Text(formatVnd(amount), style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
          ],
        ),
      );
}
