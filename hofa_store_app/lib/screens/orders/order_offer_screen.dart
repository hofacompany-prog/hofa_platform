import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';

const _acceptWindowSeconds = 120; // khớp ACCEPT_WINDOW_SECONDS trong server/src/orderOffer.js

final _offerOrderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));

/// Màn hình đơn mới cần xác nhận — mở toàn màn hình ngay khi có push (kể cả khi app đang
/// mở sẵn), có đếm ngược khớp với accept_deadline phía server. Hết giờ mà không bấm gì
/// thì tự huỷ (server cũng tự làm điều này nếu app bị đóng — xem sweepExpiredOrderOffers).
class OrderOfferScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderOfferScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderOfferScreen> createState() => _OrderOfferScreenState();
}

class _OrderOfferScreenState extends ConsumerState<OrderOfferScreen> {
  final _repo = OrderRepository();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _resolved = false;
  bool _busy = false;

  void _startCountdown(Order order) {
    _timer?.cancel();
    final deadline = order.acceptDeadline;
    if (deadline == null) return;
    void tick() {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      setState(() => _secondsLeft = remaining < 0 ? 0 : remaining);
      if (remaining <= 0) {
        _timer?.cancel();
        _autoCancelOnExpiry();
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _autoCancelOnExpiry() async {
    if (_resolved) return;
    _resolved = true;
    // Chủ động huỷ ngay để khách biết sớm, không phải chờ tới lần bấm "Nhận đơn" trễ
    // (server mới phát hiện quá hạn) hoặc chờ vòng quét nền.
    try {
      await _repo.updateStatus(widget.orderId, 'cancelled', note: 'Tự huỷ do cửa hàng không xác nhận kịp thời');
    } catch (_) {
      // im lặng — server tự chặn xác nhận trễ + vòng quét nền vẫn dọn được
    }
    if (mounted) context.pop();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await _repo.updateStatus(widget.orderId, 'confirmed');
      _resolved = true;
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
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_offerOrderProvider(widget.orderId));
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
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
              if (_timer == null) _startCountdown(order);
              return _OfferBody(
                order: order,
                secondsLeft: _secondsLeft,
                busy: _busy,
                onAccept: _accept,
                onCancel: _cancel,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OfferBody extends StatelessWidget {
  final Order order;
  final int secondsLeft;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const _OfferBody({
    required this.order,
    required this.secondsLeft,
    required this.busy,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Text('Đơn hàng mới', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(order.orderCode, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          _CountdownRing(secondsLeft: secondsLeft),
          const SizedBox(height: 24),
          Text(
            formatVnd(order.totalAmount),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
          ),
          Text(
            order.paymentMethod == 'cod' ? 'Thu hộ (COD)' : 'Đã thanh toán',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person_outline, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Giao đến', style: theme.textTheme.labelSmall),
                            Text('${order.shipRecipientName} · ${order.shipRecipientPhone}', style: theme.textTheme.titleSmall),
                            Text('${order.shipLine1}, ${order.shipProvince}', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Món hàng (${order.items.length})', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...order.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text('${item.quantity}× '),
                            Expanded(child: Text('${item.productName} ${item.variantName ?? ''}')),
                            Text(formatVnd(item.lineTotal)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: theme.colorScheme.error),
                  child: const Text('Huỷ'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Nhận đơn'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final int secondsLeft;
  const _CountdownRing({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: secondsLeft.clamp(0, _acceptWindowSeconds) / _acceptWindowSeconds,
              strokeWidth: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: secondsLeft <= 15 ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
          Text('${secondsLeft}s', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
