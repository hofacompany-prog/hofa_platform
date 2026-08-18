import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cloudinary_uploader.dart';
import '../../core/file_download.dart';
import '../../core/format.dart';
import '../../core/vietqr.dart';
import '../../models/chat_message.dart';
import '../../models/delivery.dart';
import '../../models/order.dart';
import '../../models/review.dart';
import '../../providers/app_providers.dart';
import '../../widgets/chat_badge_icon.dart';
import '../../widgets/driver_picker_dialog.dart';
import '../../widgets/full_screen_gallery_viewer.dart';
import '../../widgets/network_image_box.dart';
import 'orders_list_screen.dart' show orderStatusColor;

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  /// true khi mở màn này do khách bấm đúng thông báo "Giao hàng thành công" (xem
  /// push_service.dart#handleData) — tự bật popup mời đánh giá 1 lần, không hiện lúc khách tự
  /// vào xem đơn bình thường.
  final bool autoPromptReview;
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.autoPromptReview = false,
  });

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;
  bool _reviewPromptShown = false;
  final _reviewSectionKey = GlobalKey();

  void _maybeShowReviewPrompt(Order o) {
    if (!widget.autoPromptReview || _reviewPromptShown || !o.canReview) return;
    _reviewPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final goReview = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Đơn hàng đã giao thành công!'),
          content: Text(
            'Đơn ${o.orderCode} đã giao xong — đánh giá món ăn, cửa hàng và tài xế ngay nhé.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đánh giá ngay'),
            ),
          ],
        ),
      );
      if (goReview == true &&
          _reviewSectionKey.currentContext != null &&
          mounted) {
        await Scrollable.ensureVisible(
          _reviewSectionKey.currentContext!,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  Future<void> _cancel(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn hàng?'),
        content: Text('Đơn ${o.orderCode} sẽ bị huỷ và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Không'),
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
      await ref.read(orderRepoProvider).cancelOrder(o.id, note: 'Khách tự huỷ');
      ref.invalidate(orderDetailProvider(widget.orderId));
      ref.invalidate(
        myOrdersPagedProvider(ref.read(orderStatusFilterProvider)),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Đơn đặt trước/giá sỉ khách không tự huỷ được (xem Order.canContactMerchantToCancel) —
  /// thay bằng gọi thẳng cho cửa hàng để nhờ huỷ/hỏi hộ, không mở popup xác nhận huỷ nào cả.
  Future<void> _contactMerchant(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cửa hàng chưa cập nhật số điện thoại liên hệ'),
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không gọi được tới $phone')));
    }
  }

  /// Đơn mua hộ cần khách chọn (hoặc chọn lại, sau khi tài xế trước từ chối/hết hạn) tài xế —
  /// xem Order.needsDriverPick. Dùng chung màn chọn với checkout_screen.dart.
  Future<void> _pickDriver(Order o) async {
    final branch = await ref.read(branchDetailProvider(o.branchId).future);
    if (branch.latitude == null || branch.longitude == null || !mounted) return;
    final picked = await showDriverPickerDialog(
      context,
      lat: branch.latitude!,
      lng: branch.longitude!,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(orderRepoProvider).selectDriver(o.id, picked.id);
      ref.invalidate(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final historyAsync = ref.watch(orderHistoryProvider(widget.orderId));
    final deliveryAsync = ref.watch(orderDeliveryProvider(widget.orderId));
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
          _maybeShowReviewPrompt(o);
          final color = orderStatusColor(o.status, theme.colorScheme);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              o.orderCode,
                              style: theme.textTheme.titleLarge,
                            ),
                            Chip(
                              label: Text(
                                orderStatusLabels[o.status] ?? o.status,
                              ),
                              backgroundColor: color.withValues(alpha: 0.12),
                              side: BorderSide(
                                color: color.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Đặt lúc ${formatDateTime(o.createdAt)}'),
                        if (o.scheduledFor != null)
                          Text(
                            'Hẹn giao lúc ${formatDateTime(o.scheduledFor!)}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (o.merchantName != null) Text(o.merchantName!),
                        const Divider(height: 24),
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
                if (o.needsDriverPick) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withValues(
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
                                Icons.person_search,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cần chọn tài xế để tiếp tục đơn mua hộ',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : () => _pickDriver(o),
                              child: const Text('Chọn tài xế'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Món hàng', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ...o.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
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
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      if (item.note != null &&
                                          item.note!.trim().isNotEmpty)
                                        Text(
                                          'Ghi chú: ${item.note}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    theme.colorScheme.secondary,
                                                fontWeight: FontWeight.bold,
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
                        if (o.buyOnBehalfFee > 0)
                          _row('Phí mua hộ', formatVnd(o.buyOnBehalfFee)),
                        if (o.discountAmount > 0)
                          _row(
                            'Giảm giá',
                            '-${formatVnd(o.discountAmount)}',
                            color: theme.colorScheme.secondary,
                          ),
                        _row('Tổng cộng', formatVnd(o.totalAmount), bold: true),
                        const SizedBox(height: 4),
                        Text(
                          'Thanh toán: ${o.paymentMethod == 'cod' ? 'COD' : 'Chuyển khoản'} · ${o.paymentStatus}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (o.paymentMethod == 'bank_transfer' &&
                    o.status == 'pending_payment') ...[
                  const SizedBox(height: 12),
                  _BankTransferQrCard(order: o),
                ],
                deliveryAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, _) => const SizedBox(),
                  data: (delivery) {
                    // Đơn giá trị thấp (<= ngưỡng admin cấu hình) bỏ qua xác nhận OTP hoàn toàn
                    // — không hiện mã nữa, xem hofa-db/73_otp_threshold_settings.sql.
                    final otpMinAmount =
                        ref
                            .watch(otpSettingsProvider)
                            .valueOrNull
                            ?.minOrderAmount ??
                        0;
                    if (delivery == null ||
                        delivery.deliveryOtp == null ||
                        o.totalAmount <= otpMinAmount)
                      return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        elevation: 0,
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.12,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mã giao hàng',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                delivery.deliveryOtp!,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Đọc mã này cho tài xế khi nhận hàng để xác nhận đúng người, đúng đơn.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final chatSettings = ref
                        .watch(chatSettingsProvider)
                        .valueOrNull;
                    final chatOpen = isChatWindowOpen(
                      status: o.status,
                      deliveredAt: o.deliveredAt,
                      hoursAfterDelivered:
                          chatSettings?.hoursAfterDelivered ?? 1,
                    );
                    if (!chatOpen) return const SizedBox();
                    final hasDriver =
                        deliveryAsync.valueOrNull?.driverId != null;
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: ChatBadgeIcon(
                                orderId: o.id,
                                channel: 'customer_merchant',
                                icon: Icons.storefront_outlined,
                              ),
                              label: const Text('Nhắn tin cửa hàng'),
                              onPressed: () =>
                                  context.push('/orders/${o.id}/chat/merchant'),
                            ),
                          ),
                          if (hasDriver) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: ChatBadgeIcon(
                                  orderId: o.id,
                                  channel: 'customer_driver',
                                  icon: Icons.delivery_dining_outlined,
                                ),
                                label: const Text('Nhắn tin tài xế'),
                                onPressed: () =>
                                    context.push('/orders/${o.id}/chat/driver'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lịch sử trạng thái',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        historyAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Lỗi: $e'),
                          data: (events) => Column(
                            children: events
                                .map(
                                  (ev) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            orderStatusLabels[ev.status] ??
                                                ev.status,
                                          ),
                                        ),
                                        Text(
                                          formatDateTime(ev.createdAt),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (o.canCancel)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(o),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Huỷ đơn hàng'),
                  ),
                // Đơn đặt trước/giá sỉ — khách không tự huỷ được nữa (xem
                // Order.canContactMerchantToCancel), chỉ còn lối gọi cho cửa hàng nhờ xử lý.
                if (o.canContactMerchantToCancel)
                  Consumer(
                    builder: (context, ref, _) {
                      final merchant = ref
                          .watch(merchantDetailProvider(o.merchantId))
                          .valueOrNull;
                      return OutlinedButton.icon(
                        onPressed: () => _contactMerchant(merchant?.phone),
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Liên hệ cửa hàng để huỷ đơn'),
                      );
                    },
                  ),
                if (o.canReview) ...[
                  const SizedBox(height: 12),
                  _ReviewSection(
                    key: _reviewSectionKey,
                    order: o,
                    driver: deliveryAsync.maybeWhen(
                      data: (d) => d,
                      orElse: () => null,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
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
            Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : null,
                color: color,
              ),
            ),
          ],
        ),
      );
}

class _ReviewTarget {
  final String targetType;
  final String targetId;
  final String label;
  const _ReviewTarget({
    required this.targetType,
    required this.targetId,
    required this.label,
  });
}

/// Đánh giá món ăn (từng sản phẩm khác nhau trong đơn) + cửa hàng + tài xế, gộp trong 1 khối —
/// chỉ hiện khi Order.canReview (đã giao và còn trong 3 ngày, xem models/order.dart). Tài xế chỉ
/// hiện nếu đơn đã có delivery.driverId (đơn chưa từng có tài xế thì không có gì để đánh giá).
class _ReviewSection extends ConsumerWidget {
  final Order order;
  final Delivery? driver;
  const _ReviewSection({super.key, required this.order, this.driver});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final seenProductIds = <String>{};
    final productTargets = <_ReviewTarget>[
      for (final item in order.items)
        if (item.productId != null && seenProductIds.add(item.productId!))
          _ReviewTarget(
            targetType: 'product',
            targetId: item.productId!,
            label: item.productName,
          ),
    ];
    final targets = [
      ...productTargets,
      _ReviewTarget(
        targetType: 'merchant',
        targetId: order.merchantId,
        label: order.merchantName ?? 'Cửa hàng',
      ),
      if (driver?.driverId != null)
        _ReviewTarget(
          targetType: 'driver',
          targetId: driver!.driverId!,
          label: driver!.driverName ?? 'Tài xế',
        ),
    ];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đánh giá đơn hàng', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Đánh giá món ăn, cửa hàng và tài xế — chỉ đánh giá được trong vòng 3 ngày kể từ lúc giao hàng.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, _) {
                final existingAsync = ref.watch(orderReviewsProvider(order.id));
                return existingAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (existing) {
                    Review? findExisting(_ReviewTarget t) {
                      for (final r in existing) {
                        if (r.targetType == t.targetType &&
                            r.targetId == t.targetId)
                          return r;
                      }
                      return null;
                    }

                    return Column(
                      children: [
                        for (var i = 0; i < targets.length; i++) ...[
                          if (i > 0) const Divider(height: 24),
                          _ReviewTargetTile(
                            orderId: order.id,
                            target: targets[i],
                            existing: findExisting(targets[i]),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTargetTile extends ConsumerStatefulWidget {
  final String orderId;
  final _ReviewTarget target;
  final Review? existing;
  const _ReviewTargetTile({
    required this.orderId,
    required this.target,
    this.existing,
  });

  @override
  ConsumerState<_ReviewTargetTile> createState() => _ReviewTargetTileState();
}

const _kMaxReviewPhotos = 5;

class _ReviewTargetTileState extends ConsumerState<_ReviewTargetTile> {
  late int _rating = widget.existing?.rating ?? 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  final List<String> _mediaUrls = [];
  bool _uploadingPhoto = false;

  static const _typeLabels = {
    'merchant': 'Cửa hàng',
    'driver': 'Tài xế',
    'product': 'Món',
  };

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = _kMaxReviewPhotos - _mediaUrls.length;
    if (remaining <= 0) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (files.isEmpty) return;
    setState(() => _uploadingPhoto = true);
    try {
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        final url = await CloudinaryUploader().uploadImage(
          bytes,
          file.name,
          folder: 'reviews',
        );
        if (mounted) setState(() => _mediaUrls.add(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tải ảnh lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(reviewRepoProvider)
          .create(
            orderId: widget.orderId,
            targetType: widget.target.targetType,
            targetId: widget.target.targetId,
            rating: _rating,
            comment: _commentCtrl.text.trim(),
            mediaUrls: _mediaUrls,
          );
      ref.invalidate(orderReviewsProvider(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cảm ơn bạn đã đánh giá!')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final shownRating = existing?.rating ?? _rating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_typeLabels[widget.target.targetType] ?? ''}: ${widget.target.label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          children: List.generate(
            5,
            (i) => IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                i < shownRating ? Icons.star : Icons.star_border,
                color: Colors.amber.shade700,
              ),
              onPressed: existing != null
                  ? null
                  : () => setState(() => _rating = i + 1),
            ),
          ),
        ),
        if (existing != null) ...[
          if (existing.comment != null && existing.comment!.isNotEmpty)
            Text(existing.comment!),
          if (existing.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: existing.mediaUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) => InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => FullScreenGalleryViewer.open(
                    context,
                    images: existing.mediaUrls,
                    initialIndex: i,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: NetworkImageBox(
                      url: existing.mediaUrls[i],
                      width: 56,
                      height: 56,
                      fallbackIcon: Icons.image_outlined,
                    ),
                  ),
                ),
              ),
            ),
          ],
          Text(
            'Đã gửi đánh giá',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ] else ...[
          TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              labelText: 'Nhận xét (không bắt buộc)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _mediaUrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Stack(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => FullScreenGalleryViewer.open(
                            context,
                            images: _mediaUrls,
                            initialIndex: i,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: NetworkImageBox(
                              url: _mediaUrls[i],
                              width: 56,
                              height: 56,
                              fallbackIcon: Icons.image_outlined,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => setState(() => _mediaUrls.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_mediaUrls.length < _kMaxReviewPhotos)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _uploadingPhoto ? null : _pickPhotos,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: _uploadingPhoto
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.add_a_photo_outlined,
                              color: theme.colorScheme.outline,
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Gửi đánh giá'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Mã VietQR để khách quét chuyển khoản — chỉ hiện cho đơn bank_transfer đang pending_payment.
/// Dựng URL ảnh từ thông tin tài khoản ngân hàng admin cấu hình (bankAccountSettingsProvider),
/// không cần server tạo ảnh riêng — xem core/vietqr.dart.
class _BankTransferQrCard extends ConsumerStatefulWidget {
  final Order order;
  const _BankTransferQrCard({required this.order});

  @override
  ConsumerState<_BankTransferQrCard> createState() =>
      _BankTransferQrCardState();
}

class _BankTransferQrCardState extends ConsumerState<_BankTransferQrCard> {
  bool _downloading = false;

  Future<void> _download(String url, String filename) async {
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Không tải được ảnh QR');
      await FileDownloadService.downloadBytes(res.bodyBytes, filename);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(bankAccountSettingsProvider);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: settingsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Lỗi: $e'),
          data: (settings) {
            if (!settings.isConfigured) {
              return Text(
                'Cửa hàng chưa cấu hình mã QR chuyển khoản — liên hệ hỗ trợ để được hướng dẫn chuyển khoản.',
                style: theme.textTheme.bodyMedium,
              );
            }
            final qrUrl = buildVietQrUrl(
              bankBin: settings.bankBin!,
              accountNumber: settings.accountNumber!,
              amount: widget.order.totalAmount,
              addInfo: widget.order.orderCode,
              accountName: settings.accountHolderName,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Quét mã để chuyển khoản',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    qrUrl,
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(
                          width: 240,
                          height: 240,
                          child: Center(child: Text('Không tải được ảnh QR')),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${settings.bankName ?? ''} · ${settings.accountNumber}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (settings.accountHolderName != null)
                  Text(
                    settings.accountHolderName!,
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                Text(
                  'Số tiền: ${formatVnd(widget.order.totalAmount)} · Nội dung: ${widget.order.orderCode}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _downloading
                      ? null
                      : () => _download(
                          qrUrl,
                          'vietqr_${widget.order.orderCode}.png',
                        ),
                  icon: _downloading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: const Text('Tải QR về máy'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
