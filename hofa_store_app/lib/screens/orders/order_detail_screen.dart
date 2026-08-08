import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/delivery.dart';
import '../../models/order.dart';
import '../../models/prep_tier_settings.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/order_repository.dart';

final _orderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) => OrderRepository().get(id));
final _deliveryProvider =
    FutureProvider.autoDispose.family<Delivery?, String>((ref, id) => OrderRepository().delivery(id));
final _confirmSweepSecondsProvider =
    FutureProvider.autoDispose<int>((ref) => MerchantRepository().confirmSweepSeconds());
final _manualConfirmSweepSecondsProvider =
    FutureProvider.autoDispose<int>((ref) => MerchantRepository().manualConfirmSweepSeconds());
final _prepTierSettingsProvider =
    FutureProvider.autoDispose<PrepTierSettings>((ref) => MerchantRepository().prepTierSettings());
final _orderBranchProvider = FutureProvider.autoDispose
    .family<Branch?, ({String merchantId, String branchId})>((ref, params) async {
  final branches = await MerchantRepository().branches(params.merchantId);
  for (final b in branches) {
    if (b.id == params.branchId) return b;
  }
  return null;
});

const _fallbackPrepMinutes = 15; // dùng khi order.defaultPrepMinutes null (đơn tạo trước migration)
const _fallbackCeilingMinutes = 120; // dùng khi chưa tải được prep_ceiling_* (Thông số admin) kịp
const _defaultSweepSeconds = 10; // dùng khi chưa tải được confirm_sweep_seconds (Thông số admin) kịp
const _defaultManualSweepSeconds = 300; // dùng khi chưa tải được manual_confirm_sweep_seconds kịp

/// Chi tiết đơn — đích đến duy nhất của push "đơn mới" (xem push_service.dart) lẫn danh sách
/// đơn. Đơn "placed" luôn hiện thanh trượt xác nhận với 1 dải màu chạy, thuần phía client
/// (AnimationController riêng của màn này) — nhưng thời lượng + hậu quả hết giờ tuỳ vào công tắc
/// "Tự động nhận đơn" của chi nhánh (branches.auto_accept_orders):
///   - BẬT: chạy confirm_sweep_seconds giây (admin cấu hình ở "Thông số") — hết giờ tự chốt số
///     phút đang hiện trên bộ đếm +/- làm estimated_prep_minutes và chuyển đơn sang "confirmed".
///   - TẮT: chạy manual_confirm_sweep_seconds giây (màu khác, mặc định dài hơn nhiều) — hết giờ
///     tự HUỶ đơn và tự đóng cửa chi nhánh (is_open = false), coi như cửa hàng không theo dõi
///     đơn. Trượt tay lúc nào cũng XÁC NHẬN ngay bất kể đang ở chế độ nào, chỉ là sớm hơn.
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
  bool _sweepIsAutoAccept = true;
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

  /// Hết giờ thanh chạy màu lúc chi nhánh TẮT "Tự động nhận đơn" — huỷ đơn + đóng cửa chi
  /// nhánh, coi như cửa hàng không theo dõi đơn. Dùng chung cờ _confirmResolved với
  /// _confirmPrepTime() để 2 nhánh (BẬT/TẮT) không bao giờ cùng chạy cho 1 đơn.
  Future<void> _cancelDueToTimeout(Branch? branch) async {
    if (_confirmResolved) return;
    _confirmResolved = true;
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(widget.orderId, 'cancelled');
      if (branch != null) {
        await MerchantRepository().toggleBranchOpen(branch.id, false);
      }
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      _confirmResolved = false; // cho thử lại nếu lỗi
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
      // Thời gian chuẩn bị mặc định đã được server chốt theo bậc (auto_accept_settings.
      // prep_default_*) ngay lúc tạo đơn, xem hofa-db/39_prep_time_tiers.sql — ổn định dù admin
      // có sửa Thông số sau đó, không tính lại ở client.
      _prepMinutes ??= o.defaultPrepMinutes ?? _fallbackPrepMinutes;
      final branchAsync = ref.watch(_orderBranchProvider((merchantId: o.merchantId, branchId: o.branchId)));
      final confirmSweepAsync = ref.watch(_confirmSweepSecondsProvider);
      final manualSweepAsync = ref.watch(_manualConfirmSweepSecondsProvider);
      // Đợi tải xong CẢ 3 (chi nhánh + 2 mốc giây) rồi mới tạo controller — tạo ngay ở lần build
      // đầu tiên (lúc còn đang loading) sẽ luôn khoá cứng ở giá trị/nhánh sai vì _sweepStarted
      // bật lên true ngay, không bao giờ tạo lại controller dù dữ liệu thật đã tải xong sau đó
      // (đã xác nhận qua thực tế với riêng confirm_sweep_seconds trước đây).
      if (!_sweepStarted && !branchAsync.isLoading && !confirmSweepAsync.isLoading && !manualSweepAsync.isLoading) {
        // Mặc định coi như BẬT (an toàn hơn) nếu không tải được thông tin chi nhánh — tránh lỡ
        // tự huỷ đơn + đóng cửa hàng chỉ vì lỗi mạng tạm thời.
        final autoAccept = branchAsync.valueOrNull?.autoAcceptOrders ?? true;
        final seconds = autoAccept
            ? (confirmSweepAsync.valueOrNull ?? _defaultSweepSeconds)
            : (manualSweepAsync.valueOrNull ?? _defaultManualSweepSeconds);
        final branch = branchAsync.valueOrNull;
        _sweepStarted = true;
        _sweepIsAutoAccept = autoAccept;
        _sweepController = AnimationController(vsync: this, duration: Duration(seconds: seconds))..forward();
        _sweepController!.addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          if (autoAccept) {
            _confirmPrepTime();
          } else {
            _cancelDueToTimeout(branch);
          }
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
          child: Align(
            alignment: Alignment.topCenter,
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
    final tierSettings = ref.watch(_prepTierSettingsProvider).valueOrNull;
    final itemQuantityTotal = o.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final ceilingMinutes = tierSettings?.ceilingFor(itemQuantityTotal: itemQuantityTotal, subtotal: o.subtotal) ??
        _fallbackCeilingMinutes;
    if (_prepMinutes! > ceilingMinutes) _prepMinutes = ceilingMinutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(
                icon: Icons.remove,
                onPressed: _prepMinutes! > 1 ? () => setState(() => _prepMinutes = _prepMinutes! - 1) : null,
              ),
              SizedBox(
                width: 160,
                child: _RollingCountdown(
                  deadline: o.createdAt.add(Duration(minutes: _prepMinutes!)),
                  alignment: CrossAxisAlignment.center,
                ),
              ),
              _StepperButton(
                icon: Icons.add,
                onPressed: _prepMinutes! < ceilingMinutes ? () => setState(() => _prepMinutes = _prepMinutes! + 1) : null,
              ),
            ],
          ),
          if (_sweepStarted && !_sweepIsAutoAccept) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Chi nhánh đang tắt "Tự động nhận đơn" — hết giờ mà chưa trượt, đơn sẽ TỰ HUỶ và cửa hàng tự đóng cửa.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          _sweepController == null
              ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : _SweepSlideToConfirm(
                  sweep: _sweepController!,
                  busy: _updating,
                  onConfirm: _confirmPrepTime,
                  baseColor: _sweepIsAutoAccept ? theme.colorScheme.primary : theme.colorScheme.secondary,
                ),
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
                ? _RollingCountdown(deadline: o.confirmedAt!.add(Duration(minutes: o.estimatedPrepMinutes!)))
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
/// sau thanh trượt trong đúng thời lượng của [sweep]. Trượt hết thanh bất kỳ lúc nào = xác nhận
/// ngay; không trượt thì hết giờ [sweep] tự hoàn tất và gọi [onConfirm] hoặc tự huỷ đơn, tuỳ nơi
/// tạo controller (xem addStatusListener trong _buildBody) — server không còn tự quét/tự huỷ
/// đơn quá hạn nữa, cơ chế này thay thế hoàn toàn. [baseColor] là màu nền CHƯA chạy tới — khác
/// nhau giữa 2 chế độ (xanh lá khi BẬT "Tự động nhận đơn" = hết giờ tự xác nhận, cam khi TẮT =
/// hết giờ tự huỷ đơn) để cửa hàng phân biệt ngay hậu quả nếu không trượt kịp.
class _SweepSlideToConfirm extends StatelessWidget {
  final Animation<double> sweep;
  final bool busy;
  final Future<void> Function() onConfirm;
  final Color baseColor;

  const _SweepSlideToConfirm({
    required this.sweep,
    required this.busy,
    required this.onConfirm,
    required this.baseColor,
  });

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
      sliderButtonIcon: Icon(Icons.arrow_forward, color: baseColor),
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
                    if (usedFlex < 1000) Expanded(flex: 1000 - usedFlex, child: Container(color: baseColor)),
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

/// Đồng hồ đếm ngược thời gian chuẩn bị tới [deadline], chữ số có hiệu ứng "chạy lên/xuống" khi
/// đổi (xem [_RollingTimeText]). Hết giờ thì đóng băng ở 00:00 màu đỏ + dòng chữ báo trễ, KHÔNG
/// đếm tiếp sang số âm — đúng yêu cầu chỉ báo trạng thái, số phút trễ thật lưu ở
/// order.lateMinutes khi thực sự bấm "Đã làm xong" (xem routes/orders.js). Dùng cả TRƯỚC lúc
/// xác nhận (deadline = createdAt + số phút đang chọn trên bộ đếm +/-, tự tính lại ngay khi
/// bấm +/-) lẫn SAU khi xác nhận (deadline = confirmedAt + estimatedPrepMinutes, cố định).
class _RollingCountdown extends StatelessWidget {
  final DateTime deadline;
  final CrossAxisAlignment alignment;
  const _RollingCountdown({required this.deadline, this.alignment = CrossAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = deadline.difference(DateTime.now());
    final isLate = remaining.isNegative;
    final shown = isLate ? Duration.zero : remaining;
    final mm = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = shown.inSeconds.remainder(60).toString().padLeft(2, '0');
    final color = isLate ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: alignment,
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
