import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/order_repository.dart';

const _defaultPrepMinutes = 15; // dùng khi chưa tải được merchant.avgPrepMinutes kịp

final _offerOrderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));

/// Màn hình đơn mới cần xác nhận — mở toàn màn hình ngay khi có push (kể cả khi app đang mở
/// sẵn). Trượt thanh dưới cùng để nhận, bấm "Huỷ đơn" ở menu "...", hoặc bấm X để BỎ QUA
/// (không quyết định gì — không có thời hạn nào ép hệ thống tự xác nhận thay, cửa hàng phải
/// tự vào lại màn Đơn hàng để xử lý). Bấm X không bị chặn — cửa hàng có thể lỡ xem 1 đơn mà
/// không bị kẹt màn hình, nhưng khi đó badge đỏ ở "Đơn hàng" (Trang chủ + thanh điều hướng)
/// vẫn còn nguyên vì notification CHƯA được đánh dấu đã đọc — chỉ đánh dấu khi thực sự trượt
/// nhận/huỷ (xem _markNotificationRead).
class OrderOfferScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String? notificationId;
  const OrderOfferScreen({super.key, required this.orderId, this.notificationId});

  @override
  ConsumerState<OrderOfferScreen> createState() => _OrderOfferScreenState();
}

class _OrderOfferScreenState extends ConsumerState<OrderOfferScreen> {
  final _repo = OrderRepository();
  bool _resolved = false;
  bool _busy = false;
  int? _prepMinutes;

  void _markNotificationRead() {
    final id = widget.notificationId;
    if (id != null) NotificationRepository().markRead(id).catchError((_) {});
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await _repo.updateStatus(widget.orderId, 'confirmed', estimatedPrepMinutes: _prepMinutes);
      _resolved = true;
      _markNotificationRead();
      if (mounted) context.pushReplacement('/orders/${widget.orderId}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await _repo.updateStatus(widget.orderId, 'cancelled');
      _resolved = true;
      _markNotificationRead();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn này?'),
        content: const Text('Khách sẽ được báo đơn đã bị huỷ.'),
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
    if (ok == true) await _cancel();
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sms(String phone) async {
    final uri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_offerOrderProvider(widget.orderId));
    final merchantAsync = ref.watch(myMerchantProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: orderAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Không tải được đơn: $e', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => context.pop(), child: const Text('Đóng')),
                ],
              ),
            ),
          ),
          data: (order) {
            if (order.status != 'placed') {
              // Đã được xử lý (xác nhận/huỷ) từ nơi khác — đóng luôn.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_resolved) {
                  _resolved = true;
                  context.pop();
                }
              });
              return const Center(child: CircularProgressIndicator());
            }
            _prepMinutes ??= merchantAsync.valueOrNull?.avgPrepMinutes ?? _defaultPrepMinutes;
            return _OfferBody(
              order: order,
              busy: _busy,
              prepMinutes: _prepMinutes!,
              onPrepMinutesChanged: (v) => setState(() => _prepMinutes = v),
              onAccept: _accept,
              onCancel: _confirmCancel,
              onSkip: () => context.pop(),
              onCall: () => _call(order.shipRecipientPhone),
              onSms: () => _sms(order.shipRecipientPhone),
              onViewDetail: () => context.push('/orders/${order.id}'),
            );
          },
        ),
      ),
    );
  }
}

class _OfferBody extends StatelessWidget {
  final Order order;
  final bool busy;
  final int prepMinutes;
  final ValueChanged<int> onPrepMinutesChanged;
  final Future<void> Function() onAccept;
  final VoidCallback onCancel;
  final VoidCallback onSkip;
  final VoidCallback onCall;
  final VoidCallback onSms;
  final VoidCallback onViewDetail;

  const _OfferBody({
    required this.order,
    required this.busy,
    required this.prepMinutes,
    required this.onPrepMinutesChanged,
    required this.onAccept,
    required this.onCancel,
    required this.onSkip,
    required this.onCall,
    required this.onSms,
    required this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(tooltip: 'Bỏ qua', icon: const Icon(Icons.close), onPressed: onSkip),
              const SizedBox(width: 4),
              Text(order.orderCode, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: 'Xem chi tiết đơn',
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: onViewDetail,
              ),
              IconButton(tooltip: 'Gọi khách', icon: const Icon(Icons.call_outlined), onPressed: onCall),
              IconButton(tooltip: 'Nhắn tin', icon: const Icon(Icons.sms_outlined), onPressed: onSms),
              PopupMenuButton<void>(
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: onCancel,
                    child: Text('Huỷ đơn', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Text('${order.items.length} món', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(' cho ${order.shipRecipientName}', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.customerNote != null && order.customerNote!.trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(order.customerNote!)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Divider(height: 1),
                ...order.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  child: Text(t.name, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                                ),
                                Text(
                                  t.price > 0 ? '+${formatVnd(t.price)}' : '0',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                        if (item.note != null && item.note!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 20),
                            child: Text(
                              'Ghi chú: ${item.note}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tổng cộng', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      formatVnd(order.totalAmount),
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 18),
                    ),
                  ],
                ),
                Text(
                  order.paymentMethod == 'cod' ? 'Thu hộ (COD)' : 'Đã thanh toán',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
          ),
          child: Column(
            children: [
              Text('Thời gian làm đơn dự kiến', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StepperButton(
                    icon: Icons.remove,
                    onPressed: prepMinutes > 1 ? () => onPrepMinutesChanged(prepMinutes - 1) : null,
                  ),
                  SizedBox(
                    width: 100,
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$prepMinutes', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                            TextSpan(text: ' phút', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _StepperButton(icon: Icons.add, onPressed: () => onPrepMinutesChanged(prepMinutes + 1)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Chuẩn bị sẵn sàng đơn hàng trong thời gian này',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              // Kiểu Grab: trượt hết thanh mới tính là nhận đơn — tránh nhận nhầm khi lỡ chạm.
              SlideAction(
                key: ValueKey(order.id),
                enabled: !busy,
                text: 'Xác nhận',
                textStyle: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                outerColor: theme.colorScheme.primary,
                innerColor: Colors.white,
                sliderButtonIcon: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
                height: 60,
                borderRadius: 30,
                onSubmit: onAccept,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _StepperButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: onPressed == null ? theme.colorScheme.outline : theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
