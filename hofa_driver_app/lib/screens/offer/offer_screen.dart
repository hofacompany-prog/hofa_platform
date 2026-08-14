import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/delivery.dart';
import '../../models/order.dart' as model;
import '../../providers/auth_provider.dart';
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';
import '../delivery/delivery_detail_screen.dart';

final _offerOrderProvider = FutureProvider.autoDispose
    .family<model.Order, String>((ref, id) => OrderRepository().get(id));
final _offerBranchProvider = FutureProvider.autoDispose.family<Branch, String>(
  (ref, id) => PickupRepository().branch(id),
);

/// Màn hình đơn giao hàng mới cần xác nhận — mở toàn màn hình ngay khi có push (kể cả khi app
/// đang mở sẵn). Luôn hiện thanh trượt xác nhận với 1 dải màu chạy, thuần phía client
/// (AnimationController riêng của màn này) trong đúng khoảng deliveries.accept_deadline mà
/// server đã tính sẵn (xem dispatch.offerToNearestDriver) — thời lượng + hậu quả hết giờ tuỳ
/// vào công tắc "Tự động nhận đơn" của chính tài xế (drivers.auto_accept, đổi ở Trang chủ):
///   - BẬT: thanh xanh chạy ngắn (driver_accept_settings.auto_accept_sweep_seconds, admin cấu
///     hình ở "Thông số tài xế") — hết giờ tự chốt "Nhận đơn" luôn.
///   - TẮT: thanh cam chạy dài hơn (manual_accept_sweep_seconds) — hết giờ tự chuyển đơn cho
///     tài xế gần nhất tiếp theo.
/// Khác bên cửa hàng (đã bỏ hẳn quét server): driver app GIỮ server làm nguồn xác thực chính
/// (accept_deadline + sweepExpiredOffers quét mỗi 10s, xem dispatch.js) vì tài xế di chuyển
/// ngoài đường, mạng không ổn định bằng cửa hàng — thanh màu ở đây chỉ là hiển thị trực quan +
/// tự gọi API sớm hơn (không đợi vòng quét), không tự thay thế server.
///
/// Sau khi nhận đơn (hoặc phát hiện đơn đã được xử lý từ nơi khác), KHÔNG điều hướng sang
/// route khác — build() tự chuyển sang hiện DeliveryDetailScreen ngay tại đây (cùng route
/// /offer/:id), liền mạch từ lúc xác nhận sang lúc theo dõi chuyến, không có hiệu ứng chuyển
/// màn hình.
class OfferScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const OfferScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen>
    with SingleTickerProviderStateMixin {
  final _deliveryRepo = DeliveryRepository();
  AnimationController? _sweepController;
  bool _sweepStarted = false;
  bool _sweepIsAutoAccept = true;
  bool _resolved = false;
  bool _busy = false;

  /// Chặn thoát màn này bằng nút back của TRÌNH DUYỆT (web) — PopScope(canPop: false) chỉ chặn
  /// được pop kiểu Flutter Navigator, không chặn được back của trình duyệt (đã xác nhận qua
  /// thực tế). router.dart tự đẩy trở lại /offer/:id ở redirect nếu biến này còn set — PHẢI
  /// xoá trước khi tự điều hướng đi (accept/decline) để không tự đá chính mình quay lại.
  void _setPendingOffer() {
    if (ref.read(pendingOfferIdProvider) != widget.deliveryId) {
      ref.read(pendingOfferIdProvider.notifier).state = widget.deliveryId;
    }
  }

  void _clearPendingOffer() {
    if (ref.read(pendingOfferIdProvider) == widget.deliveryId) {
      ref.read(pendingOfferIdProvider.notifier).state = null;
    }
  }

  /// Rời màn này sau khi đơn đã được xử lý xong (nhận/từ chối/đóng do lỗi) — màn /offer/:id
  /// nhiều lúc là route DUY NHẤT trên stack (router.dart tự redirect thẳng vào đây khi
  /// pendingOfferIdProvider còn set, kể cả lúc mở app từ trạng thái tắt hẳn qua push), context.pop()
  /// khi đó ném GoError "There is nothing to pop" — chỉ pop được nếu thật sự có gì để pop, không
  /// thì về thẳng trang chủ.
  void _closeOffer() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _clearPendingOffer();
    _sweepController?.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_resolved) return;
    _resolved = true;
    setState(() => _busy = true);
    try {
      await _deliveryRepo.updateStatus(widget.deliveryId, 'accepted');
      _clearPendingOffer();
      ref.invalidate(activeDeliveryProvider);
      // KHÔNG điều hướng sang route khác — build() bên dưới tự chuyển sang hiện
      // DeliveryDetailScreen ngay tại màn này khi deliveryProvider refetch thấy status đổi,
      // liền mạch từ lúc xác nhận sang lúc theo dõi chuyến, không có hiệu ứng chuyển màn.
      ref.invalidate(deliveryProvider(widget.deliveryId));
    } catch (e) {
      _resolved = false; // cho thử lại (tự động hoặc trượt tay) nếu lỗi
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hết giờ thanh chạy màu lúc tài xế TẮT "Tự động nhận đơn" — chủ động gọi decline ngay
  /// (thay vì đợi tới lúc server quét, tối đa 10s) để đơn được chuyển cho tài xế khác sớm hơn.
  Future<void> _declineOnExpiry() async {
    if (_resolved) return;
    _resolved = true;
    try {
      await _deliveryRepo.decline(widget.deliveryId);
    } catch (_) {
      // im lặng — server tự chặn accept trễ + vòng quét vẫn dọn được dù gọi lỗi ở đây
    }
    _clearPendingOffer();
    if (mounted) _closeOffer();
  }

  Future<void> _decline() async {
    if (_resolved) return;
    _resolved = true;
    setState(() => _busy = true);
    try {
      await _deliveryRepo.decline(widget.deliveryId);
      _clearPendingOffer();
      if (mounted) _closeOffer();
    } catch (e) {
      _resolved = false;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final deliveryAsync = ref.watch(deliveryProvider(widget.deliveryId));
    final theme = Theme.of(context);

    return deliveryAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Không tải được đơn: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    _clearPendingOffer();
                    _closeOffer();
                  },
                  child: const Text('Đóng'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (delivery) {
        if (delivery.status != 'assigned') {
          // Đã được xác nhận (từ chính màn này hay nơi khác, vd auto-accept lúc hết giờ) hoặc
          // đã bị từ chối/hết hạn ở nơi khác — hiện LUÔN màn chi tiết chuyến giao ngay tại đây
          // (cùng route /offer/:id, không điều hướng đi đâu cả) thay vì đóng màn. Không còn
          // PopScope(canPop:false) ở nhánh này — DeliveryDetailScreen tự có Scaffold/AppBar
          // riêng, đóng/back bình thường được vì đơn đã có chủ, không cần ép quyết định nữa.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _clearPendingOffer(),
          );
          return DeliveryDetailScreen(deliveryId: widget.deliveryId);
        }
        // ref.read(...).state = ... không được gọi thẳng trong build() (Riverpod chặn sửa
        // provider lúc cây widget đang dựng) — hoãn sang sau khung hình này.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setPendingOffer();
        });
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: theme.colorScheme.surface,
            body: SafeArea(child: _buildBody(context, delivery)),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, Delivery delivery) {
    final theme = Theme.of(context);
    final driverAsync = ref.watch(myDriverProvider);
    final orderAsync = ref.watch(_offerOrderProvider(delivery.orderId));

    // Đợi tải xong myDriverProvider rồi mới tạo controller — tạo ngay ở lần build đầu tiên
    // (lúc còn đang loading) sẽ luôn khoá cứng ở autoAccept=false vì _sweepStarted bật lên
    // true ngay, không bao giờ tạo lại controller dù dữ liệu thật đã tải xong sau đó (đã xác
    // nhận qua thực tế với confirm_sweep_seconds bên store app trước đây).
    if (!_sweepStarted && !driverAsync.isLoading) {
      // QUAN TRỌNG: AnimationController.duration là tổng thời lượng CHO CẢ QUÃNG 0→1, không
      // phải "thời gian còn lại" — nếu chỉ truyền thời gian còn lại rồi forward() từ 0 như
      // trước, thanh sẽ hiện lại RỖNG rồi chạy nhanh hơn hẳn (chỉ trong phần thời gian còn lại)
      // trông như 1 lượt đếm MỚI, NGẮN HƠN — dễ khiến tài xế hiểu lầm là bị reset. Đúng ra phải
      // giữ nguyên TỔNG thời lượng gốc (assignedAt → acceptDeadline), chỉ nhảy thẳng tới đúng %
      // đã trôi qua (forward(from: ...)) để thanh tiếp tục đúng chỗ đã thoát ra, cùng tốc độ.
      final Duration totalDuration;
      final double startValue;
      if (delivery.acceptDeadline != null && delivery.assignedAt != null) {
        totalDuration = delivery.acceptDeadline!.difference(
          delivery.assignedAt!,
        );
        final elapsed = DateTime.now().difference(delivery.assignedAt!);
        startValue = totalDuration.inMilliseconds > 0
            ? (elapsed.inMilliseconds / totalDuration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 1.0;
      } else {
        totalDuration = Duration.zero;
        startValue = 1.0;
      }
      _sweepStarted = true;
      _sweepIsAutoAccept = driverAsync.valueOrNull?.autoAccept ?? false;
      _sweepController = AnimationController(
        vsync: this,
        duration: totalDuration > Duration.zero
            ? totalDuration
            : const Duration(milliseconds: 1),
      );
      _sweepController!.addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        if (_sweepIsAutoAccept) {
          _accept();
        } else {
          _declineOnExpiry();
        }
      });
      _sweepController!.forward(from: startValue);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Đơn giao hàng mới',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              orderAsync.when(
                data: (order) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Gọi khách',
                      icon: const Icon(Icons.call_outlined),
                      onPressed: () => _call(order.shipRecipientPhone),
                    ),
                    IconButton(
                      tooltip: 'Nhắn tin',
                      icon: const Icon(Icons.sms_outlined),
                      onPressed: () => _sms(order.shipRecipientPhone),
                    ),
                  ],
                ),
                loading: () => const SizedBox(),
                error: (_, _) => const SizedBox(),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AmountChip(
                      icon: Icons.route,
                      label: delivery.distanceKm != null
                          ? '${delivery.distanceKm!.toStringAsFixed(1)} km'
                          : '—',
                    ),
                    _AmountChip(
                      icon: Icons.timer_outlined,
                      label: delivery.etaMinutes != null
                          ? '${delivery.etaMinutes} phút'
                          : '—',
                    ),
                    _AmountChip(
                      icon: Icons.payments,
                      label: formatVnd(delivery.driverFee),
                      highlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                orderAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Không tải được đơn: $e'),
                  data: (order) => _OfferDetails(order: order),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              if (_sweepStarted && !_sweepIsAutoAccept) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Bạn đang tắt "Tự động nhận đơn" — hết giờ mà chưa trượt, đơn sẽ chuyển cho tài xế khác.',
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
                      busy: _busy,
                      onConfirm: _accept,
                      baseColor: _sweepIsAutoAccept
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary,
                    ),
              // Bật "Tự động nhận đơn" thì không cho từ chối tay — hết giờ thanh trượt sẽ tự
              // nhận đơn (xem addStatusListener ở trên), nút "Từ chối" ở đây chỉ có ý nghĩa khi
              // tài xế đang TẮT chế độ đó.
              if (!_sweepIsAutoAccept) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _decline,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Từ chối đơn này'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _AmountChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          icon,
          color: highlight
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
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

class _OfferDetails extends ConsumerWidget {
  final model.Order order;
  const _OfferDetails({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchAsync = ref.watch(_offerBranchProvider(order.branchId));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        branchAsync.when(
          data: (branch) => _AddressTile(
            icon: Icons.storefront,
            label: 'Lấy hàng',
            title: branch.displayName,
            subtitle: branch.fullLine,
          ),
          loading: () => const _AddressTile(
            icon: Icons.storefront,
            label: 'Lấy hàng',
            title: 'Đang tải...',
            subtitle: '',
          ),
          error: (_, _) => const _AddressTile(
            icon: Icons.storefront,
            label: 'Lấy hàng',
            title: '—',
            subtitle: '',
          ),
        ),
        if (branchAsync.valueOrNull?.isBuyOnBehalf == true) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đơn mua hộ — bạn cần ứng tiền mua hàng tại quán, được hoàn ngay vào ví khi xác nhận đã mua xong (không cần OTP, chỉ cần ảnh hoá đơn).',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        if (order.shipNote != null && order.shipNote!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
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
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.shipNote!,
                    style: TextStyle(color: theme.colorScheme.secondary),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '${order.orderCode} · ${order.items.length} món · '
          '${order.paymentMethod == 'cod' ? 'Thu hộ ${formatVnd(order.totalAmount)}' : 'Đã thanh toán'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  const _AddressTile({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
  });

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
              if (subtitle.isNotEmpty)
                Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thanh trượt xác nhận nhận đơn — dải màu cảnh báo chạy dần từ trái sang phải phía sau thanh
/// trượt trong đúng thời lượng của [sweep] (đã khớp deliveries.accept_deadline server tính
/// sẵn). Trượt hết thanh bất kỳ lúc nào = nhận đơn ngay; không trượt thì hết giờ [sweep] tự
/// hoàn tất và gọi [onConfirm] hoặc tự chuyển tài xế khác, tuỳ nơi tạo controller (xem
/// addStatusListener trong _buildBody). [baseColor] là màu nền CHƯA chạy tới — khác nhau giữa 2
/// chế độ (xanh lá khi BẬT "Tự động nhận đơn" = hết giờ tự nhận, cam khi TẮT = hết giờ tự
/// chuyển tài xế khác) để tài xế phân biệt ngay hậu quả nếu không trượt kịp.
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
      key: const ValueKey('offer-accept-slide'),
      enabled: !busy,
      text: 'Trượt để nhận đơn',
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
