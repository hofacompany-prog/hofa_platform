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
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/rolling_countdown.dart';

final _orderProvider = FutureProvider.autoDispose.family<Order, String>(
  (ref, id) => OrderRepository().get(id),
);
final _deliveryProvider = FutureProvider.autoDispose.family<Delivery?, String>(
  (ref, id) => OrderRepository().delivery(id),
);
final _confirmSweepSecondsProvider = FutureProvider.autoDispose<int>(
  (ref) => MerchantRepository().confirmSweepSeconds(),
);
final _manualConfirmSweepSecondsProvider = FutureProvider.autoDispose<int>(
  (ref) => MerchantRepository().manualConfirmSweepSeconds(),
);
final _prepTierSettingsProvider = FutureProvider.autoDispose<PrepTierSettings>(
  (ref) => MerchantRepository().prepTierSettings(),
);
final _orderBranchProvider = FutureProvider.autoDispose
    .family<Branch?, ({String merchantId, String branchId})>((
      ref,
      params,
    ) async {
      final branches = await MerchantRepository().branches(params.merchantId);
      for (final b in branches) {
        if (b.id == params.branchId) return b;
      }
      return null;
    });

const _fallbackPrepMinutes =
    15; // dùng khi order.defaultPrepMinutes null (đơn tạo trước migration)
const _fallbackCeilingMinutes =
    120; // dùng khi chưa tải được prep_ceiling_* (Thông số admin) kịp
const _defaultSweepSeconds =
    10; // dùng khi chưa tải được confirm_sweep_seconds (Thông số admin) kịp
const _defaultManualSweepSeconds =
    300; // dùng khi chưa tải được manual_confirm_sweep_seconds kịp

/// Chi tiết đơn — đích đến duy nhất của push "đơn mới" (xem push_service.dart) lẫn danh sách
/// đơn. Đơn "placed" luôn hiện thanh trượt xác nhận với 1 dải màu chạy, thuần phía client
/// (AnimationController riêng của màn này) — nhưng thời lượng + hậu quả hết giờ tuỳ vào công tắc
/// "Tự động nhận đơn" của chi nhánh (branches.auto_accept_orders):
///   - BẬT: chạy confirm_sweep_seconds giây (admin cấu hình ở "Thông số") — hết giờ tự chốt số
///     phút đang hiện trên bộ đếm +/- làm estimated_prep_minutes và chuyển đơn sang "confirmed".
///   - TẮT: chạy manual_confirm_sweep_seconds giây (màu khác, mặc định dài hơn nhiều) — hết giờ
///     tự HUỶ đơn và tự đóng cửa chi nhánh (is_open = false), coi như cửa hàng không theo dõi
///     đơn. Trượt tay lúc nào cũng XÁC NHẬN ngay bất kể đang ở chế độ nào, chỉ là sớm hơn.
/// Mốc hết giờ của thanh chạy màu (o.confirmSweepDeadline) đã được SERVER chốt sẵn ngay lúc
/// tạo đơn (hofa-db/42_confirm_sweep_deadline.sql) — thoát app rồi mở lại đúng đơn này chỉ tính
/// lại thời gian còn LẠI tới đúng mốc đó, không reset về đầu.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _updating = false;
  AnimationController? _sweepController;
  bool _sweepStarted = false;
  bool _sweepIsAutoAccept = true;
  bool _confirmResolved = false;
  int? _prepMinutes;

  @override
  void dispose() {
    _sweepController?.dispose();
    super.dispose();
  }

  Future<void> _confirmPrepTime() async {
    if (_confirmResolved) return;
    _confirmResolved = true;
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(
        widget.orderId,
        'confirmed',
        estimatedPrepMinutes: _prepMinutes,
      );
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      _confirmResolved = false; // cho thử lại (tự động hoặc trượt tay) nếu lỗi
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tìm thấy tài xế, đang chờ xác nhận'),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn?'),
        content: const Text(
          'Đơn sẽ chuyển sang trạng thái đã huỷ, hàng đã giữ chỗ sẽ được nhả lại.',
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
    setState(() => _updating = true);
    try {
      await OrderRepository().updateStatus(widget.orderId, 'cancelled');
      ref.invalidate(_orderProvider(widget.orderId));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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

  Widget _buildBody(
    BuildContext context,
    Order o,
    AsyncValue<Delivery?> deliveryAsync,
  ) {
    final theme = Theme.of(context);
    // Đơn đặt trước còn "ngủ" (xem Order.isPreorderPending, hofa-db/49_preorder_gating.sql) vẫn
    // status='placed' nhưng chưa tới lúc thao tác được — loại khỏi isPlaced để tự động tắt luôn
    // thanh trượt xác nhận (block bên dưới), nút "Đã làm xong"/"Huỷ đơn" (canCancel).
    final isPlaced = o.status == 'placed' && !o.isPreorderPending;
    final isPrepPhase = o.status == 'confirmed' || o.status == 'preparing';
    final canCancel = isPlaced || isPrepPhase;

    if (isPlaced) {
      // Thời gian chuẩn bị mặc định đã được server chốt theo bậc (auto_accept_settings.
      // prep_default_*) ngay lúc tạo đơn, xem hofa-db/39_prep_time_tiers.sql — ổn định dù admin
      // có sửa Thông số sau đó, không tính lại ở client.
      _prepMinutes ??= o.defaultPrepMinutes ?? _fallbackPrepMinutes;
      final branchAsync = ref.watch(
        _orderBranchProvider((merchantId: o.merchantId, branchId: o.branchId)),
      );
      // o.confirmSweepDeadline đã được server chốt SẴN lúc tạo đơn (hofa-db/
      // 42_confirm_sweep_deadline.sql) — dùng mốc giờ cố định này thay vì tự tính lại số giây
      // mỗi lần mở màn, để thoát app rồi vào lại KHÔNG làm thanh chạy lại từ đầu (đã xác nhận
      // qua thực tế: trước đây thanh luôn reset về 100% mỗi lần mở lại màn hình). Đơn tạo trước
      // migration (confirmSweepDeadline null) mới cần đợi tải confirm_sweep_seconds/
      // manual_confirm_sweep_seconds để tự tính tạm 1 mốc mới, xem nhánh else bên dưới.
      final confirmSweepAsync = ref.watch(_confirmSweepSecondsProvider);
      final manualSweepAsync = ref.watch(_manualConfirmSweepSecondsProvider);
      final needsFallbackSettings = o.confirmSweepDeadline == null;
      final settingsReady =
          !needsFallbackSettings ||
          (!confirmSweepAsync.isLoading && !manualSweepAsync.isLoading);
      // Đợi tải xong thông tin chi nhánh (+ 2 mốc giây NẾU đơn cũ chưa có deadline) rồi mới tạo
      // controller — tạo ngay ở lần build đầu tiên (lúc còn đang loading) sẽ luôn khoá cứng ở
      // giá trị/nhánh sai vì _sweepStarted bật lên true ngay, không bao giờ tạo lại controller
      // dù dữ liệu thật đã tải xong sau đó (đã xác nhận qua thực tế với riêng
      // confirm_sweep_seconds trước đây).
      if (!_sweepStarted && !branchAsync.isLoading && settingsReady) {
        // Mặc định coi như BẬT (an toàn hơn) nếu không tải được thông tin chi nhánh — tránh lỡ
        // tự huỷ đơn + đóng cửa hàng chỉ vì lỗi mạng tạm thời.
        final autoAccept = branchAsync.valueOrNull?.autoAcceptOrders ?? true;
        final branch = branchAsync.valueOrNull;

        // QUAN TRỌNG: AnimationController.duration là tổng thời lượng CHO CẢ QUÃNG 0→1, không
        // phải "thời gian còn lại" — nếu chỉ truyền thời gian còn lại rồi forward() từ 0 như
        // trước, thanh sẽ hiện lại RỖNG rồi chạy nhanh hơn hẳn (chỉ trong phần thời gian còn
        // lại) trông như một lượt đếm MỚI, NGẮN HƠN — dễ khiến cửa hàng hiểu lầm là bị reset.
        // Đúng ra phải giữ nguyên TỔNG thời lượng gốc, chỉ nhảy thẳng tới đúng % đã trôi qua
        // (forward(from: ...)) để thanh tiếp tục đúng chỗ đã thoát ra, cùng tốc độ như ban đầu.
        final Duration totalDuration;
        final double startValue;
        if (o.confirmSweepDeadline != null) {
          // confirmSweepDeadline và createdAt được chốt CÙNG 1 now() trong create_order() (cùng
          // 1 transaction Postgres) — hiệu số này chính XÁC là tổng thời lượng ban đầu.
          totalDuration = o.confirmSweepDeadline!.difference(o.createdAt);
          final elapsed = DateTime.now().difference(o.createdAt);
          startValue = totalDuration.inMilliseconds > 0
              ? (elapsed.inMilliseconds / totalDuration.inMilliseconds).clamp(
                  0.0,
                  1.0,
                )
              : 1.0;
        } else {
          // Đơn cũ tạo trước migration 42 — chưa có mốc backend, coi như vừa bắt đầu ngay bây giờ.
          totalDuration = Duration(
            seconds: autoAccept
                ? (confirmSweepAsync.valueOrNull ?? _defaultSweepSeconds)
                : (manualSweepAsync.valueOrNull ?? _defaultManualSweepSeconds),
          );
          startValue = 0.0;
        }
        _sweepStarted = true;
        _sweepIsAutoAccept = autoAccept;
        _sweepController = AnimationController(
          vsync: this,
          duration: totalDuration > Duration.zero
              ? totalDuration
              : const Duration(milliseconds: 1),
        );
        _sweepController!.addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          if (autoAccept) {
            _confirmPrepTime();
          } else {
            _cancelDueToTimeout(branch);
          }
        });
        _sweepController!.forward(from: startValue);
      }
    }

    return Column(
      children: [
        _buildHeader(context, o, canCancel),
        if (o.isPreorderPending) _buildPreorderBanner(context, o),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      TextSpan(text: '${o.items.length} món'),
                      TextSpan(
                        text: ' cho ${o.shipRecipientName}',
                        style: const TextStyle(fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (ref
                            .watch(myMerchantProvider)
                            .valueOrNull
                            ?.merchantType ==
                        'buy_on_behalf') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: theme.colorScheme.tertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Đơn mua hộ — hệ thống tự chuyển thẳng cho tài xế xử lý ngay khi khách thanh toán, cửa hàng không cần xác nhận/chuẩn bị.',
                                style: TextStyle(
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (o.customerNote != null &&
                        o.customerNote!.trim().isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: theme.colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                o.customerNote!,
                                style: TextStyle(
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ),
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
                                Text(
                                  '${item.quantity} x ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.variantName != null &&
                                            item.variantName!.isNotEmpty
                                        ? '${item.productName} (${item.variantName})'
                                        : item.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatVnd(item.lineTotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            for (final t in item.toppings)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  left: 20,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.name,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.outline,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      t.price > 0
                                          ? '+${formatVnd(t.price)}'
                                          : '0',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            if (item.note != null &&
                                item.note!.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  left: 20,
                                ),
                                child: Text(
                                  'Ghi chú: ${item.note}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.bold,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (o.paymentGroupOrderId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Khách đã chuyển khoản gộp 1 lần cho cả tuần — không cần chờ thanh toán riêng cho đơn này',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Trước đây chỉ huỷ được qua menu "⋮" ở đầu trang — thêm hẳn 1 nút ngay
                    // dưới danh sách món cho dễ thấy, cùng logic với mục "Huỷ đơn" trong đó
                    // (_confirmCancel), chỉ hiện khi đơn còn ở giai đoạn huỷ được.
                    if (canCancel) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.icon(
                          onPressed: _updating ? null : _confirmCancel,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Huỷ đơn'),
                        ),
                      ),
                    ],
                    deliveryAsync.when(
                      loading: () => const SizedBox(),
                      error: (_, _) => const SizedBox(),
                      data: (delivery) {
                        if (delivery == null || delivery.pickupOtp == null)
                          return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Card(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.10,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mã lấy hàng',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    delivery.pickupOtp!,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 4,
                                          color: theme.colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Đọc mã này cho tài xế khi họ đến lấy hàng.',
                                    style: theme.textTheme.bodySmall,
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

  /// Đơn đặt trước còn "ngủ" — giải thích vì sao không thấy thanh xác nhận/nút thao tác nào,
  /// tránh cửa hàng tưởng bị lỗi. Thời điểm kích hoạt = scheduled_for trừ default_prep_minutes,
  /// đúng ngưỡng sweepDuePreorders phía server dùng.
  Widget _buildPreorderBanner(BuildContext context, Order o) {
    final theme = Theme.of(context);
    final prepMinutes = o.defaultPrepMinutes ?? _fallbackPrepMinutes;
    final activatesAt = o.scheduledFor?.subtract(
      Duration(minutes: prepMinutes),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activatesAt != null
                  ? 'Đơn đặt trước — chỉ xem được món lúc này, sẽ xử lý được lúc ${formatDateTime(activatesAt)}'
                  : 'Đơn đặt trước — chỉ xem được món lúc này, chưa thao tác được',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
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
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              o.orderCode,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Gọi khách',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _call(o.shipRecipientPhone),
          ),
          IconButton(
            tooltip: 'Nhắn tin',
            icon: const Icon(Icons.sms_outlined),
            onPressed: () => _sms(o.shipRecipientPhone),
          ),
          if (canCancel)
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: _confirmCancel,
                  child: Text(
                    'Huỷ đơn',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPlacedBottom(BuildContext context, Order o) {
    final theme = Theme.of(context);
    final tierSettings = ref.watch(_prepTierSettingsProvider).valueOrNull;
    final itemQuantityTotal = o.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final ceilingMinutes =
        tierSettings?.ceilingFor(
          itemQuantityTotal: itemQuantityTotal,
          subtotal: o.subtotal,
        ) ??
        _fallbackCeilingMinutes;
    if (_prepMinutes! > ceilingMinutes) _prepMinutes = ceilingMinutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(
                icon: Icons.remove,
                onPressed: _prepMinutes! > 1
                    ? () => setState(() => _prepMinutes = _prepMinutes! - 1)
                    : null,
              ),
              SizedBox(
                width: 160,
                child: RollingCountdown(
                  deadline: o.createdAt.add(Duration(minutes: _prepMinutes!)),
                  alignment: CrossAxisAlignment.center,
                ),
              ),
              _StepperButton(
                icon: Icons.add,
                onPressed: _prepMinutes! < ceilingMinutes
                    ? () => setState(() => _prepMinutes = _prepMinutes! + 1)
                    : null,
              ),
            ],
          ),
          if (_sweepStarted && !_sweepIsAutoAccept) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Chi nhánh đang tắt "Tự động nhận đơn" — hết giờ mà chưa trượt, đơn sẽ TỰ HUỶ và cửa hàng tự đóng cửa.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          _sweepController == null
              ? const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _SweepSlideToConfirm(
                  sweep: _sweepController!,
                  busy: _updating,
                  onConfirm: _confirmPrepTime,
                  baseColor: _sweepIsAutoAccept
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: o.confirmedAt != null && o.estimatedPrepMinutes != null
                ? RollingCountdown(
                    deadline: o.confirmedAt!.add(
                      Duration(minutes: o.estimatedPrepMinutes!),
                    ),
                  )
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
        Text(
          label,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        Text(
          formatVnd(amount),
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
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
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null
                ? theme.colorScheme.outline
                : theme.colorScheme.onSurface,
          ),
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
      textStyle: theme.textTheme.titleMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
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
                      Expanded(
                        flex: usedFlex,
                        child: Container(
                          color: theme.colorScheme.error.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                    if (usedFlex < 1000)
                      Expanded(
                        flex: 1000 - usedFlex,
                        child: Container(color: baseColor),
                      ),
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
