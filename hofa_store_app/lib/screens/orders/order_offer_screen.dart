import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slide_to_act/slide_to_act.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';

const _acceptWindowSeconds = 20; // khớp ACCEPT_WINDOW_SECONDS trong server/src/orderOffer.js

final _offerOrderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));

/// Màn hình đơn mới cần xác nhận — mở toàn màn hình ngay khi có push (kể cả khi app đang
/// mở sẵn), có đếm ngược khớp với accept_deadline phía server. Trượt thanh dưới cùng để
/// nhận, hoặc bấm "Huỷ đơn"; hết giờ mà không làm gì thì TỰ ĐỘNG NHẬN (server cũng tự làm
/// điều này nếu app bị đóng — xem sweepExpiredOrderOffers).
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
        _autoConfirmOnExpiry();
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Hết 20s mà không trượt nhận/huỷ — TỰ ĐỘNG NHẬN (không tự huỷ), vì mất đơn của khách
  /// chỉ vì chậm 20s là trải nghiệm tệ hơn nhiều so với việc cửa hàng phải tự lo 1 đơn lỡ
  /// quên trượt. Chủ động gọi ngay ở đây để khách/cửa hàng biết sớm, không phải chờ server
  /// (route tự xử lý y hệt nếu bấm trễ) hay vòng quét nền.
  Future<void> _autoConfirmOnExpiry() async {
    if (_resolved) return;
    _resolved = true;
    try {
      await _repo.updateStatus(widget.orderId, 'confirmed');
    } catch (_) {
      // im lặng — server/vòng quét nền tự xác nhận hộ được, không chặn màn hình vì lỗi mạng thoáng qua
    }
    if (mounted) context.pushReplacement('/orders/${widget.orderId}');
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
  final Future<void> Function() onAccept;
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
          TextButton(
            onPressed: busy ? null : onCancel,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Huỷ đơn'),
          ),
          const SizedBox(height: 8),
          // Kiểu Grab: trượt hết thanh mới tính là nhận đơn — tránh nhận nhầm khi lỡ chạm.
          SlideAction(
            key: ValueKey(order.id),
            enabled: !busy,
            text: 'Trượt để nhận đơn ($secondsLeft s)',
            textStyle: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            outerColor: theme.colorScheme.primary,
            innerColor: Colors.white,
            sliderButtonIcon: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
            height: 64,
            borderRadius: 32,
            onSubmit: onAccept,
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
              // Đỏ khi còn dưới 1/4 thời gian — tỉ lệ, không phải số giây cố định, để không
              // bị đỏ gần hết vòng đời nếu sau này đổi _acceptWindowSeconds.
              color: secondsLeft <= (_acceptWindowSeconds * 0.25).round()
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          Text('${secondsLeft}s', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
