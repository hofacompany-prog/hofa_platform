import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/delivery.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';

final _orderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));
final _deliveryProvider =
    FutureProvider.autoDispose.family<Delivery?, String>((ref, id) => OrderRepository().delivery(id));

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _updating = false;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Chỉ để làm mới đồng hồ đếm ngược chuẩn bị đơn mỗi giây, không gắn hành động nào.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

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

  /// Bấm 1 lần là "báo xong" — đi thẳng tới "Chờ tài xế lấy" (thông báo khách + tự tìm tài xế,
  /// xem PATCH /orders/:id/status), dù state machine DB vẫn bắt buộc qua 'preparing' trước
  /// (hofa-db/04_api_functions.sql) nên nếu đơn còn ở 'confirmed' thì gọi ngầm 2 bước liền nhau.
  Future<void> _markDone(String currentStatus) async {
    setState(() => _updating = true);
    try {
      if (currentStatus == 'confirmed') {
        await OrderRepository().updateStatus(widget.orderId, 'preparing');
      }
      await OrderRepository().updateStatus(widget.orderId, 'ready_for_pickup');
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _findDriver() async {
    setState(() => _updating = true);
    try {
      await OrderRepository().findDriver(widget.orderId);
      ref.invalidate(_orderProvider(widget.orderId));
      ref.invalidate(_deliveryProvider(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tìm thấy tài xế, đang chờ xác nhận')));
      }
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
    final deliveryAsync = ref.watch(_deliveryProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết đơn hàng')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (o) {
          final next = nextMerchantStatus[o.status];
          final canCancel = ['placed', 'confirmed', 'preparing'].contains(o.status);
          final isPrepPhase = o.status == 'confirmed' || o.status == 'preparing';
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
                                Expanded(
                                  child: Text(
                                    o.orderCode,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Chip(label: Text(orderStatusLabels[o.status] ?? o.status)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${o.items.length} món · Đặt lúc ${formatDateTime(o.createdAt)}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
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
                            ...o.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${item.quantity} x ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Expanded(
                                          child: Text(
                                            item.variantName != null && item.variantName!.isNotEmpty
                                                ? '${item.productName} (${item.variantName})'
                                                : item.productName,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        Text(formatVnd(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    for (final t in item.toppings)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4, left: 20),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                t.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                                              ),
                                            ),
                                            Text(
                                              t.price > 0 ? '+${formatVnd(t.price)}' : '0',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (item.note != null && item.note!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4, left: 20),
                                        child: Text(
                                          'Ghi chú: ${item.note}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.outline,
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(),
                            _totalRow('Tổng tiền món', o.subtotal, bold: true),
                            const SizedBox(height: 4),
                            Text('Thanh toán: ${o.paymentMethod.toUpperCase()} · ${o.paymentStatus}'),
                          ],
                        ),
                      ),
                    ),
                    deliveryAsync.when(
                      loading: () => const SizedBox(),
                      error: (_, _) => const SizedBox(),
                      data: (delivery) {
                        if (delivery == null || delivery.pickupOtp == null) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Card(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Mã lấy hàng', style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 4),
                                  Text(
                                    delivery.pickupOtp!,
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 4,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Đọc mã này cho tài xế khi họ đến lấy hàng.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (o.status == 'ready_for_pickup') ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _updating ? null : _findDriver,
                        icon: const Icon(Icons.search),
                        label: const Text('Tìm tài xế'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Hệ thống đã tự tìm khi đơn chuyển sang trạng thái này. Bấm lại nếu lúc đó chưa có tài xế nào online.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    if (isPrepPhase && o.confirmedAt != null && o.estimatedPrepMinutes != null) ...[
                      const SizedBox(height: 16),
                      _PrepCountdownCard(confirmedAt: o.confirmedAt!, estimatedPrepMinutes: o.estimatedPrepMinutes!),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        if (isPrepPhase)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _updating ? null : () => _markDone(o.status),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Đã làm xong'),
                            ),
                          )
                        else if (next != null)
                          Expanded(
                            child: FilledButton(
                              onPressed: _updating ? null : () => _updateStatus(next),
                              child: Text('Chuyển sang "${orderStatusLabels[next]}"'),
                            ),
                          ),
                        if ((isPrepPhase || next != null) && canCancel) const SizedBox(width: 12),
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

/// Đồng hồ chuẩn bị đơn — chạy từ lúc xác nhận (confirmedAt), hạn là estimatedPrepMinutes.
/// Còn hạn thì hiện "Còn lại MM:SS", quá hạn thì chuyển đỏ "Đã trễ N phút" (chỉ hiển thị —
/// late_minutes thật sự được server chốt khi bấm "Đã làm xong", xem PATCH /orders/:id/status).
class _PrepCountdownCard extends StatelessWidget {
  final DateTime confirmedAt;
  final int estimatedPrepMinutes;
  const _PrepCountdownCard({required this.confirmedAt, required this.estimatedPrepMinutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deadline = confirmedAt.add(Duration(minutes: estimatedPrepMinutes));
    final remaining = deadline.difference(DateTime.now());
    final isLate = remaining.isNegative;
    final shown = isLate ? -remaining : remaining;
    final mm = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = shown.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      color: isLate ? theme.colorScheme.errorContainer : theme.colorScheme.primary.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isLate ? Icons.warning_amber_rounded : Icons.timer_outlined,
              color: isLate ? theme.colorScheme.onErrorContainer : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isLate ? 'Đã trễ ${shown.inMinutes} phút' : 'Còn lại $mm:$ss để chuẩn bị đơn',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isLate ? theme.colorScheme.onErrorContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
