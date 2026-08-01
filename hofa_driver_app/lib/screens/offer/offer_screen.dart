import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/delivery.dart';
import '../../models/order.dart' as model;
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';

/// Màn hình đơn mới cần xác nhận — mở toàn màn hình ngay khi có push (kể cả khi app
/// đang mở sẵn), có đếm ngược khớp với accept_deadline phía server. Hết giờ mà không
/// bấm gì thì tự coi như từ chối (server cũng tự làm điều này nếu app bị đóng).
class OfferScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const OfferScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  final _deliveryRepo = DeliveryRepository();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _resolved = false;
  bool _busy = false;

  void _startCountdown(Delivery delivery) {
    _timer?.cancel();
    final deadline = delivery.acceptDeadline;
    if (deadline == null) return;
    void tick() {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      setState(() => _secondsLeft = remaining < 0 ? 0 : remaining);
      if (remaining <= 0) {
        _timer?.cancel();
        _autoDeclineOnExpiry();
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _autoDeclineOnExpiry() async {
    if (_resolved) return;
    _resolved = true;
    // Chủ động gọi decline để đơn được chuyển ngay cho tài xế khác, không phải chờ
    // tới lần tài xế này bấm "Nhận đơn" trễ (server mới phát hiện quá hạn) hoặc chờ cron quét.
    try {
      await _deliveryRepo.decline(widget.deliveryId);
    } catch (_) {
      // im lặng — server tự chặn accept trễ + cron quét (nếu có cấu hình) vẫn dọn được
    }
    if (mounted) context.pop();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await _deliveryRepo.updateStatus(widget.deliveryId, 'accepted');
      _resolved = true;
      ref.invalidate(activeDeliveryProvider);
      if (mounted) context.pushReplacement('/deliveries/${widget.deliveryId}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await _deliveryRepo.decline(widget.deliveryId);
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
    final deliveryAsync = ref.watch(deliveryProvider(widget.deliveryId));
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: deliveryAsync.when(
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
            data: (delivery) {
              if (delivery.status != 'assigned') {
                // Đã được xử lý (chấp nhận/hết hạn) từ nơi khác — đóng luôn.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_resolved) {
                    _resolved = true;
                    context.pop();
                  }
                });
                return const Center(child: CircularProgressIndicator());
              }
              if (_timer == null) _startCountdown(delivery);
              return _OfferBody(
                delivery: delivery,
                secondsLeft: _secondsLeft,
                busy: _busy,
                onAccept: _accept,
                onDecline: _decline,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OfferBody extends StatelessWidget {
  final Delivery delivery;
  final int secondsLeft;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _OfferBody({
    required this.delivery,
    required this.secondsLeft,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Text('Đơn giao hàng mới', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _CountdownRing(secondsLeft: secondsLeft),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AmountChip(icon: Icons.route, label: delivery.distanceKm != null ? '${delivery.distanceKm!.toStringAsFixed(1)} km' : '—'),
              _AmountChip(icon: Icons.payments, label: formatVnd(delivery.driverFee), highlight: true),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: _OfferDetails(orderId: delivery.orderId)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: theme.colorScheme.error),
                  child: const Text('Từ chối'),
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
              value: (secondsLeft.clamp(0, 60)) / 25,
              strokeWidth: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: secondsLeft <= 5 ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
          Text('${secondsLeft}s', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _AmountChip({required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: highlight ? theme.colorScheme.primary : theme.colorScheme.outline),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

class _OfferDetails extends StatelessWidget {
  final String orderId;
  const _OfferDetails({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<model.Order>(
      future: OrderRepository().get(orderId),
      builder: (context, orderSnap) {
        if (!orderSnap.hasData) return const Center(child: CircularProgressIndicator());
        final order = orderSnap.data!;
        return FutureBuilder<Branch>(
          future: PickupRepository().branch(order.branchId),
          builder: (context, branchSnap) {
            final theme = Theme.of(context);
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AddressTile(
                    icon: Icons.storefront,
                    label: 'Lấy hàng',
                    title: branchSnap.data?.name ?? 'Đang tải...',
                    subtitle: branchSnap.data?.fullLine ?? '',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 19),
                    child: SizedBox(height: 20, child: VerticalDivider(thickness: 2)),
                  ),
                  _AddressTile(
                    icon: Icons.flag,
                    label: 'Giao hàng',
                    title: order.shipRecipientName,
                    subtitle: order.shipFullAddress,
                  ),
                  const SizedBox(height: 8),
                  Text('${order.orderCode} · ${order.items.length} món · ${order.paymentMethod == 'cod' ? 'Thu hộ ${formatVnd(order.totalAmount)}' : 'Đã thanh toán'}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AddressTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  const _AddressTile({required this.icon, required this.label, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(title, style: theme.textTheme.titleSmall),
              if (subtitle.isNotEmpty) Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
