import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../models/delivery.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/order_repository.dart';

final _orderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));
final _deliveryProvider =
    FutureProvider.autoDispose.family<Delivery?, String>((ref, id) => OrderRepository().delivery(id));

const _defaultPrepMinutes = 15; // dùng khi chưa tải được merchant.avgPrepMinutes kịp

/// Chi tiết đơn — đích đến duy nhất của push "đơn mới" (xem push_service.dart) lẫn danh sách
/// đơn. Đơn "placed" hiện thanh trượt xác nhận với 1 dải màu chạy trong 10 giây thuần phía
/// client (AnimationController riêng của màn này) — hết 10s mà cửa hàng chưa trượt thì tự
/// chốt số phút đang hiện trên bộ đếm +/- làm estimated_prep_minutes và chuyển đơn sang
/// "confirmed"; trượt tay lúc nào cũng làm y hệt vậy, chỉ là sớm hơn.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> with SingleTickerProviderStateMixin {
  bool _updating = false;
  Timer? _tickTimer;
  AnimationController? _sweepController;
  bool _sweepStarted = false;
  bool _confirmResolved = false;
  int? _prepMinutes;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _sweepController?.dispose();
    super.dispose();
  }

  Future<void> _confirmPrepTime() async {
    if (_confirmResolved) return;
    _confirmResolved = true;
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(widget.orderId, 'confirmed', estimatedPrepMinutes: _prepMinutes);
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      _confirmResolved = false; // cho thử lại (tự động hoặc trượt tay) nếu lỗi
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

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
    if (ok != true) return;
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(widget.orderId, 'cancelled');
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
    final orderAsync = ref.watch(_orderProvider(widget.orderId));
    final deliveryAsync = ref.watch(_deliveryProvider(widget.orderId));
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: orderAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (o) => _buildBody(context, o, deliveryAsync),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Order o, AsyncValue<Delivery?> deliveryAsync) {
    final theme = Theme.of(context);
    final isPlaced = o.status == 'placed';
    final isPrepPhase = o.status == 'confirmed' || o.status == 'preparing';
    final canCancel = isPlaced || isPrepPhase;

    if (isPlaced) {
      final merchant = ref.watch(myMerchantProvider).valueOrNull;
      _prepMinutes ??= merchant?.avgPrepMinutes ?? _defaultPrepMinutes;
      if (!_sweepStarted) {
        _sweepStarted = true;
        _sweepController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..forward();
        _sweepController!.addStatusListener((status) {
          if (status == AnimationStatus.completed) _confirmPrepTime();
        });
      }
    }

    return Column(
      children: [
        _buildHeader(context, o, canCancel),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Text('${o.items.length} món', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Chip(label: Text(orderStatusLabels[o.status] ?? o.status)),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đặt lúc ${formatDateTime(o.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    if (o.customerNote != null && o.customerNote!.trim().isNotEmpty) ...[
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
                            Expanded(child: Text(o.customerNote!)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Divider(height: 1),
                    ...o.items.map(
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
                                      child: Text(
                                        t.name,
                                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                                      ),
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
                    _totalRow('Tổng tiền món', o.subtotal, bold: true),
                    const SizedBox(height: 4),
                    Text(
                      'Thanh toán: ${o.paymentMethod.toUpperCase()} · ${o.paymentStatus}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    deliveryAsync.when(
                      loading: () => const SizedBox(),
                      error: (_, _) => const SizedBox(),
                      data: (delivery) {
                        if (delivery == null || delivery.pickupOtp == null) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Card(
                            color: theme.colorScheme.primary.withValues(alpha: 0.10),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Mã lấy hàng', style: theme.textTheme.titleSmall),
                                  const SizedBox(height: 4),
                                  Text(
                                    delivery.pickupOtp!,
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 4,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Đọc mã này cho tài xế khi họ đến lấy hàng.', style: theme.textTheme.bodySmall),
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
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isPlaced) _buildPlacedBottom(context, o),
        if (isPrepPhase) _buildPrepPhaseBottom(context, o),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Order o, bool canCancel) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Đóng',
            icon: const Icon(Icons.close),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              o.orderCode,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(tooltip: 'Gọi khách', icon: const Icon(Icons.call_outlined), onPressed: () => _call(o.shipRecipientPhone)),
          IconButton(tooltip: 'Nhắn tin', icon: const Icon(Icons.sms_outlined), onPressed: () => _sms(o.shipRecipientPhone)),
          if (canCancel)
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(onTap: _confirmCancel, child: Text('Huỷ đơn', style: TextStyle(color: theme.colorScheme.error))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPlacedBottom(BuildContext context, Order o) {
    final theme = Theme.of(context);
    return Container(
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
                onPressed: _prepMinutes! > 1 ? () => setState(() => _prepMinutes = _prepMinutes! - 1) : null,
              ),
              SizedBox(
                width: 100,
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_prepMinutes!}',
                          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' phút', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
              _StepperButton(icon: Icons.add, onPressed: () => setState(() => _prepMinutes = _prepMinutes! + 1)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chuẩn bị sẵn sàng đơn hàng trong thời gian này',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          _SweepSlideToConfirm(sweep: _sweepController!, busy: _updating, onConfirm: _confirmPrepTime),
        ],
      ),
    );
  }

  Widget _buildPrepPhaseBottom(BuildContext context, Order o) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: o.confirmedAt != null && o.estimatedPrepMinutes != null
                ? _RollingCountdown(confirmedAt: o.confirmedAt!, estimatedPrepMinutes: o.estimatedPrepMinutes!)
                : const SizedBox(),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _updating ? null : () => _markDone(o.status),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Đã làm xong'),
          ),
        ],
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

/// Thanh trượt xác nhận thời gian chuẩn bị — dải màu cảnh báo chạy dần từ trái sang phải phía
/// sau thanh trượt trong đúng 10 giây (điều khiển bởi [sweep], KHÔNG liên quan
/// order.acceptDeadline). Trượt hết thanh bất kỳ lúc nào = xác nhận ngay; không trượt thì hết
/// 10 giây [sweep] tự hoàn tất và gọi [onConfirm] (xem addStatusListener ở nơi tạo controller).
class _SweepSlideToConfirm extends StatelessWidget {
  final Animation<double> sweep;
  final bool busy;
  final Future<void> Function() onConfirm;

  const _SweepSlideToConfirm({required this.sweep, required this.busy, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = SlideAction(
      key: const ValueKey('confirm-prep-slide'),
      enabled: !busy,
      text: 'Xác nhận',
      textStyle: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      outerColor: Colors.transparent,
      innerColor: Colors.white,
      sliderButtonIcon: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
      height: 60,
      borderRadius: 30,
      onSubmit: onConfirm,
    );

    return Stack(
      children: [
        AnimatedBuilder(
          animation: sweep,
          builder: (context, _) {
            final usedFlex = (sweep.value * 1000).round().clamp(0, 1000);
            return ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    if (usedFlex > 0)
                      Expanded(flex: usedFlex, child: Container(color: theme.colorScheme.error.withValues(alpha: 0.55))),
                    if (usedFlex < 1000)
                      Expanded(flex: 1000 - usedFlex, child: Container(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            );
          },
        ),
        slide,
      ],
    );
  }
}

/// Đồng hồ đếm ngược thời gian chuẩn bị, chữ số có hiệu ứng "chạy lên/xuống" khi đổi (xem
/// [_RollingTimeText]). Hết giờ thì đóng băng ở 00:00 màu đỏ + dòng chữ báo trễ, KHÔNG đếm tiếp
/// sang số âm hay số phút trễ — đúng yêu cầu chỉ báo trạng thái, số phút trễ thật lưu ở
/// order.lateMinutes khi thực sự bấm "Đã làm xong" (xem routes/orders.js).
class _RollingCountdown extends StatelessWidget {
  final DateTime confirmedAt;
  final int estimatedPrepMinutes;
  const _RollingCountdown({required this.confirmedAt, required this.estimatedPrepMinutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deadline = confirmedAt.add(Duration(minutes: estimatedPrepMinutes));
    final remaining = deadline.difference(DateTime.now());
    final isLate = remaining.isNegative;
    final shown = isLate ? Duration.zero : remaining;
    final mm = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = shown.inSeconds.remainder(60).toString().padLeft(2, '0');
    final color = isLate ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RollingTimeText(
          text: '$mm:$ss',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          isLate ? 'Đơn hàng đang bị trễ' : 'Thời gian chuẩn bị còn lại',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isLate ? theme.colorScheme.error : theme.colorScheme.outline,
            fontWeight: isLate ? FontWeight.bold : null,
          ),
        ),
      ],
    );
  }
}

/// Hiệu ứng đồng hồ cơ học: từng ký tự tự trượt lên và mờ dần vào/ra riêng, dùng
/// AnimatedSwitcher keyed theo (vị trí, ký tự) — chỉ ký tự vừa đổi mới chạy hiệu ứng.
class _RollingTimeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _RollingTimeText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < text.length; i++)
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Text(text[i], key: ValueKey('$i-${text[i]}'), style: style),
            ),
          ),
      ],
    );
  }
}
