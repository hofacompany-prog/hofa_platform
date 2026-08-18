import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import 'orders_screen.dart' show statusColor;
import '../../core/responsive.dart';

class AdminOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const AdminOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<AdminOrderDetailScreen> createState() =>
      _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState
    extends ConsumerState<AdminOrderDetailScreen> {
  bool _busy = false;

  /// Admin gọi API với p_force=true nên bỏ qua được state machine — dùng khi cần
  /// gỡ đơn bị kẹt. Hỏi xác nhận vì đây là thao tác ghi đè quy trình bình thường.
  Future<void> _forceStatus(Order o) async {
    var selected = o.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Chuyển trạng thái đơn'),
          content: SizedBox(
            width: dialogWidth(context, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quyền admin cho phép chuyển sang bất kỳ trạng thái nào, kể cả ngược quy trình.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: allOrderStatuses
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(orderStatusLabels[s] ?? s),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setInner(() => selected = v ?? selected),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Chuyển'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selected == o.status) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepoProvider)
          .updateOrderStatus(o.id, selected, note: 'Admin chuyển thủ công');
      ref.invalidate(orderDetailProvider(widget.orderId));
      ref.invalidate(ordersProvider);
      ref.invalidate(statsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Đơn đang kẹt chờ tài xế (đã báo qua notifyAdmins, xem
  /// dispatch.js#sweepDriverSearch) — chọn quét tiếp thì reset về 0 lần, sweep tự thử lại
  /// từ chu kỳ kế tiếp.
  Future<void> _continueDriverSearch(Order o) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).continueDriverSearch(o.id);
      ref.invalidate(orderDetailProvider(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cho quét tiếp')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelForNoDriver(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn?'),
        content: Text(
          'Đơn ${o.orderCode} sẽ chuyển sang trạng thái "Đã huỷ" vì không tìm được tài xế nào '
          'nhận sau ${o.driverSearchAttempts} lần quét.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Huỷ đơn'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepoProvider)
          .updateOrderStatus(
            o.id,
            'cancelled',
            note:
                'Admin huỷ — không tìm được tài xế sau ${o.driverSearchAttempts} lần quét',
          );
      ref.invalidate(orderDetailProvider(widget.orderId));
      ref.invalidate(ordersProvider);
      ref.invalidate(statsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDialog(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá đơn hàng?'),
        content: Text(
          'Đơn ${o.orderCode} sẽ bị xoá vĩnh viễn, không thể khôi phục. Nếu đơn còn dữ liệu '
          'liên quan chặn xoá (vd giao dịch thanh toán), hệ thống sẽ báo lỗi cụ thể.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).deleteOrder(o.id);
      ref.invalidate(ordersProvider);
      ref.invalidate(statsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá đơn ${o.orderCode}')));
        context.go('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : null,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : null,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/orders'),
        ),
        title: const Text('Chi tiết đơn hàng'),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (o) {
          final color = statusColor(o.status, theme.colorScheme);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (o.driverSearchAlertedAt != null) ...[
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.errorContainer.withValues(
                          alpha: 0.5,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Chưa tìm được tài xế sau ${o.driverSearchAttempts} lần quét',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.error,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _cancelForNoDriver(o),
                                    child: const Text('Huỷ đơn'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _continueDriverSearch(o),
                                    child: const Text('Quét tiếp'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    o.orderCode,
                                    style: theme.textTheme.headlineSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Đặt lúc ${formatDateTime(o.createdAt)}'),
                            const Divider(height: 28),
                            Text('Giao đến', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text(
                              '${o.shipRecipientName} · ${o.shipRecipientPhone}',
                            ),
                            Text('${o.shipLine1}, ${o.shipProvince}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Món hàng', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            ...o.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${item.quantity}× '),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item.productName} ${item.variantName ?? ''}',
                                          ),
                                          if (item.toppings.isNotEmpty)
                                            Text(
                                              item.toppings
                                                  .map((t) => t.name)
                                                  .join(', '),
                                              style:
                                                  theme.textTheme.bodySmall,
                                            ),
                                          if (item.note != null &&
                                              item.note!.trim().isNotEmpty)
                                            Text(
                                              'Ghi chú: ${item.note}',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .secondary,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(formatVnd(item.lineTotal)),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 24),
                            _row('Tạm tính', formatVnd(o.subtotal)),
                            _row('Phí giao hàng', formatVnd(o.deliveryFee)),
                            if (o.discountAmount > 0)
                              _row(
                                'Giảm giá',
                                '-${formatVnd(o.discountAmount)}',
                                color: theme.colorScheme.secondary,
                              ),
                            _row(
                              'Tổng cộng',
                              formatVnd(o.totalAmount),
                              bold: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Thanh toán: ${o.paymentMethod.toUpperCase()} · ${o.paymentStatus}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _forceStatus(o),
                      icon: const Icon(Icons.edit),
                      label: const Text('Chuyển trạng thái thủ công'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _deleteDialog(o),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Xoá đơn hàng'),
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
}
