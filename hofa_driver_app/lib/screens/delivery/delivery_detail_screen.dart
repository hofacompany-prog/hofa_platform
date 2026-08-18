import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../core/maps_launcher.dart';
import '../../models/branch.dart';
import '../../models/chat_message.dart';
import '../../models/delivery.dart';
import '../../models/order.dart' as model;
import '../../providers/auth_provider.dart';
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';
import '../../widgets/chat_badge_icon.dart';
import '../../widgets/image_upload_field.dart';

const _stageOrder = [
  'accepted',
  'arrived_store',
  'picked_up',
  'delivering',
  'delivered',
];

/// Nhãn ngắn riêng cho stepper — không dùng chung deliveryStatusLabels vì hầu hết bắt đầu bằng
/// "Đã" (Đã nhận đơn, Đã đến quán, Đã lấy hàng...), lấy từ đầu sẽ ra toàn chữ "Đã".
const _stageShortLabels = {
  'accepted': 'Đã nhận',
  'arrived_store': 'Đến quán',
  'picked_up': 'Lấy hàng',
  'delivering': 'Đang giao',
  'delivered': 'Giao xong',
};

class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<DeliveryDetailScreen> createState() =>
      _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  final _repo = DeliveryRepository();
  bool _busy = false;
  bool _loadingContext = false;
  model.Order? _order;
  Branch? _branch;

  /// Đơn giá trị THẤP HƠN HOẶC BẰNG ngưỡng admin cấu hình thì bỏ qua xác nhận OTP hoàn toàn —
  /// xem hofa-db/73_otp_threshold_settings.sql. Chưa tải xong _order thì mặc định BẮT BUỘC
  /// (an toàn hơn — không lỡ bỏ qua xác nhận thật cần thiết).
  bool get _otpRequired {
    final order = _order;
    if (order == null) return true;
    final minAmount =
        ref.read(otpSettingsProvider).valueOrNull?.minOrderAmount ?? 0;
    return order.totalAmount > minAmount;
  }

  Future<void> _loadContext(String orderId) async {
    if (_order != null || _loadingContext) return;
    _loadingContext = true;
    try {
      final order = await OrderRepository().get(orderId);
      final branch = await PickupRepository().branch(order.branchId);
      if (mounted) {
        setState(() {
          _order = order;
          _branch = branch;
        });
      }
    } catch (_) {
      // hiện lỗi ngay trong build() qua FutureBuilder riêng nếu cần — ở đây bỏ qua để không chặn stepper
    } finally {
      _loadingContext = false;
    }
  }

  Future<void> _advance(
    String nextStatus, {
    String? otp,
    String? recipientName,
    List<String>? proofPhotoUrls,
    String? failureReason,
  }) async {
    setState(() => _busy = true);
    try {
      await _repo.updateStatus(
        widget.deliveryId,
        nextStatus,
        otp: otp,
        recipientName: recipientName,
        proofPhotoUrls: proofPhotoUrls,
        failureReason: failureReason,
      );
      ref.invalidate(deliveryProvider(widget.deliveryId));
      ref.invalidate(activeDeliveryProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promptOtp(String title, String nextStatus) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nhập mã OTP'),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _advance(nextStatus, otp: ctrl.text.trim());
  }

  Future<void> _promptDelivered() async {
    final otpCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? photoUrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã giao'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_otpRequired) ...[
                TextField(
                  controller: otpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mã OTP khách đọc cho bạn',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Người nhận (không bắt buộc)',
                ),
              ),
              const SizedBox(height: 16),
              ImageUploadField(
                label: 'Ảnh xác nhận đã giao (không bắt buộc)',
                folder: 'deliveries',
                onChanged: (url) => photoUrl = url,
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
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_otpRequired && otpCtrl.text.trim().isEmpty) return;
    await _advance(
      'delivered',
      otp: otpCtrl.text.trim().isEmpty ? null : otpCtrl.text.trim(),
      recipientName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      proofPhotoUrls: photoUrl != null ? [photoUrl!] : null,
    );
  }

  /// Đơn mua hộ — tài xế tự đi mua, không có nhân viên cửa hàng nào đọc OTP cho tài xế, nên
  /// bước "picked_up" ở đây không hỏi OTP mà bắt buộc 1 ảnh hoá đơn/hàng đã mua làm bằng chứng
  /// (xem update_delivery_status trong hofa-db/43_buy_on_behalf_driver_dispatch.sql — server
  /// chặn hẳn nếu thiếu ảnh). Ví tài xế được hoàn tiền hàng ngay khi xác nhận thành công.
  Future<void> _promptBuyOnBehalfPickup() async {
    String? photoUrl;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Xác nhận đã mua xong'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đơn mua hộ — không cần OTP, chỉ cần chụp ảnh hoá đơn hoặc hàng đã mua làm bằng chứng.',
                ),
                const SizedBox(height: 12),
                ImageUploadField(
                  label: 'Ảnh hoá đơn/hàng đã mua (bắt buộc)',
                  folder: 'deliveries',
                  onChanged: (url) => setInner(() {
                    photoUrl = url;
                    error = null;
                  }),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () {
                if (photoUrl == null) {
                  setInner(() => error = 'Cần chụp ảnh trước khi xác nhận');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || photoUrl == null) return;
    await _advance('picked_up', proofPhotoUrls: [photoUrl!]);
  }

  Future<void> _promptFailed() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Báo giao thất bại'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Lý do'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _advance('failed', failureReason: ctrl.text.trim());
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Quán đóng cửa, không lấy được hàng — hiện SĐT khách để tài xế tự gọi báo, kèm nút gọi
  /// nhanh luôn (tái dùng _call). Không tự động gọi ngay, để tài xế chủ động bấm.
  Future<void> _reportClosedToCustomer() async {
    final phone = _order?.shipRecipientPhone;
    if (phone == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Báo khách hàng'),
        content: Text('Quán đã đóng cửa — gọi cho khách để báo:\n\n$phone'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _call(phone);
            },
            icon: const Icon(Icons.call),
            label: const Text('Gọi ngay'),
          ),
        ],
      ),
    );
  }

  /// Báo mọi admin biết quán này đang đóng cửa (server/src/routes/deliveries.js
  /// POST /deliveries/:id/report-branch-closed → push.notifyAdmins) để admin xem xét đóng cửa
  /// tạm thời quán đó trong bao lâu — không tự đổi trạng thái đơn/chuyến, chỉ là báo cáo.
  Future<void> _reportClosedToAdmin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Báo admin quán đóng cửa'),
        content: const Text(
          'Xác nhận quán này đã đóng cửa? Admin sẽ được báo ngay để xem xét đóng cửa tạm thời quán này trên hệ thống.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.reportBranchClosed(widget.deliveryId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã báo admin — cảm ơn bạn!')),
        );
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

  @override
  Widget build(BuildContext context) {
    final deliveryAsync = ref.watch(deliveryProvider(widget.deliveryId));
    // watch (không chỉ read) để provider thực sự tải — dùng ở _otpRequired qua ref.read.
    ref.watch(otpSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _order != null ? 'Đơn ${_order!.orderCode}' : 'Chuyến giao hàng',
        ),
        actions: [
          IconButton(
            tooltip: 'Bản đồ',
            icon: const Icon(Icons.map_outlined),
            onPressed: () =>
                context.push('/deliveries/${widget.deliveryId}/map'),
          ),
        ],
      ),
      body: deliveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (delivery) {
          _loadContext(delivery.orderId);
          final order = _order;
          final branch = _branch;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              _StageStepper(status: delivery.status),
              const SizedBox(height: 16),
              if (delivery.isBuyOnBehalf && order != null)
                _BuyOnBehalfShoppingCard(order: order),
              if (delivery.isBuyOnBehalf && order != null)
                const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storefront,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              branch?.displayName ?? 'Đang tải...',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (branch != null)
                            IconButton(
                              icon: const Icon(Icons.directions),
                              onPressed: () => launchDirections(
                                branch.latitude,
                                branch.longitude,
                              ),
                            ),
                          if (branch?.phone != null)
                            IconButton(
                              icon: const Icon(Icons.call_outlined),
                              onPressed: () => _call(branch!.phone!),
                            ),
                        ],
                      ),
                      if (branch != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Text(branch.fullLine),
                        ),
                    ],
                  ),
                ),
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
                      Row(
                        children: [
                          Icon(Icons.flag, color: theme.colorScheme.secondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Khách hàng',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                Text(
                                  order?.shipRecipientName ?? 'Đang tải...',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ],
                            ),
                          ),
                          if (order != null && order.shipLatitude != null)
                            IconButton(
                              icon: const Icon(Icons.directions),
                              onPressed: () => launchDirections(
                                order.shipLatitude!,
                                order.shipLongitude!,
                              ),
                            ),
                          if (order != null)
                            IconButton(
                              icon: const Icon(Icons.call_outlined),
                              onPressed: () => _call(order.shipRecipientPhone),
                            ),
                          if (order != null &&
                              isChatWindowOpen(
                                status: order.status,
                                deliveredAt: order.deliveredAt,
                                hoursAfterDelivered:
                                    ref
                                        .watch(chatSettingsProvider)
                                        .valueOrNull
                                        ?.hoursAfterDelivered ??
                                    1,
                              ))
                            IconButton(
                              icon: ChatBadgeIcon(
                                orderId: order.id,
                                channel: 'customer_driver',
                                icon: Icons.chat_bubble_outline,
                              ),
                              onPressed: () =>
                                  context.push('/orders/${order.id}/chat'),
                            ),
                        ],
                      ),
                      if (order != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Text(order.shipFullAddress),
                        ),
                      if (order?.shipNote != null &&
                          order!.shipNote!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 32, top: 4),
                          child: Text(
                            'Ghi chú: ${order.shipNote}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (order?.customerNote != null &&
                  order!.customerNote!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
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
                            order.customerNote!,
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!delivery.isBuyOnBehalf && order != null) ...[
                const SizedBox(height: 12),
                _OrderItemsCard(order: order),
              ],
              const SizedBox(height: 12),
              _PayoutBreakdownCard(delivery: delivery),
              if (order != null && order.paymentMethod == 'cod')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Thu hộ khách: ${formatVnd(order.totalAmount)} (COD)',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _ActionArea(
                status: delivery.status,
                failureReason: delivery.failureReason,
                busy: _busy,
                isBuyOnBehalf: delivery.isBuyOnBehalf,
                onArrivedStore: () => _advance('arrived_store'),
                onPickedUp: _otpRequired
                    ? () => _promptOtp(
                        'Nhập mã OTP lấy hàng (cửa hàng đọc cho bạn)',
                        'picked_up',
                      )
                    : () => _advance('picked_up'),
                onBuyOnBehalfPickup: _promptBuyOnBehalfPickup,
                onStartDelivering: () => _advance('delivering'),
                onDelivered: _promptDelivered,
                onFailed: _promptFailed,
                onReportClosedToCustomer: order == null
                    ? null
                    : _reportClosedToCustomer,
                onReportClosedToAdmin: _reportClosedToAdmin,
                onReportPrice: order == null
                    ? null
                    : () => context.push(
                        '/merchants/${order.merchantId}/report-price',
                      ),
                onDone: () => context.go('/'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StageStepper extends StatelessWidget {
  final String status;
  const _StageStepper({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = status == 'failed' || status == 'returned';
    final currentIndex = failed
        ? _stageOrder.length
        : _stageOrder.indexOf(status);

    return Row(
      children: [
        for (var i = 0; i < _stageOrder.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: i <= currentIndex
                      ? (failed
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: i < currentIndex || (i == currentIndex && !failed)
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  _stageShortLabels[_stageOrder[i]]!,
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (i != _stageOrder.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: i < currentIndex
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
              ),
            ),
        ],
      ],
    );
  }
}

class _ActionArea extends StatelessWidget {
  final String status;
  final String? failureReason;
  final bool busy;
  final bool isBuyOnBehalf;
  final VoidCallback onArrivedStore;
  final VoidCallback onPickedUp;
  final VoidCallback onBuyOnBehalfPickup;
  final VoidCallback onStartDelivering;
  final VoidCallback onDelivered;
  final VoidCallback onFailed;
  final VoidCallback? onReportClosedToCustomer;
  final VoidCallback onReportClosedToAdmin;
  final VoidCallback? onReportPrice;
  final VoidCallback onDone;

  const _ActionArea({
    required this.status,
    required this.failureReason,
    required this.busy,
    required this.isBuyOnBehalf,
    required this.onArrivedStore,
    required this.onPickedUp,
    required this.onBuyOnBehalfPickup,
    required this.onStartDelivering,
    required this.onDelivered,
    required this.onFailed,
    required this.onReportClosedToCustomer,
    required this.onReportClosedToAdmin,
    required this.onReportPrice,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case 'accepted':
        return FilledButton.icon(
          onPressed: busy ? null : onArrivedStore,
          icon: const Icon(Icons.storefront),
          label: Text(isBuyOnBehalf ? 'Đã đến quán' : 'Đã đến quán lấy hàng'),
        );
      case 'arrived_store':
        return Column(
          children: [
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : (isBuyOnBehalf ? onBuyOnBehalfPickup : onPickedUp),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(isBuyOnBehalf ? 'Đã mua xong hàng' : 'Đã lấy hàng'),
            ),
            const SizedBox(height: 16),
            Text(
              'Quán đã đóng cửa, không lấy được hàng?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReportClosedToCustomer,
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Báo khách hàng'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReportClosedToAdmin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('Báo admin'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (busy || onReportPrice == null)
                    ? null
                    : onReportPrice,
                icon: const Icon(Icons.price_change_outlined),
                label: const Text('Báo giá sai'),
              ),
            ),
          ],
        );
      case 'picked_up':
        return FilledButton.icon(
          onPressed: busy ? null : onStartDelivering,
          icon: const Icon(Icons.delivery_dining),
          label: const Text('Bắt đầu giao hàng'),
        );
      case 'delivering':
        return Column(
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onDelivered,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Đã giao xong'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : onFailed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.error_outline),
              label: const Text('Báo giao thất bại'),
            ),
          ],
        );
      case 'delivered':
        return Column(
          children: [
            Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text('Đã giao hàng thành công', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: const Text('Về trang chủ')),
          ],
        );
      case 'failed':
        return Column(
          children: [
            Icon(
              Icons.cancel_outlined,
              color: theme.colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Giao thất bại${failureReason != null ? ': $failureReason' : ''}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: const Text('Về trang chủ')),
          ],
        );
      default:
        return const SizedBox();
    }
  }
}

/// Số tiền tài xế thực nhận cho chuyến này, kèm breakdown hoa hồng/thuế GTGT/TNCN (cùng cách
/// hiển thị với "Tài chính" ở app cửa hàng) — xem hofa-db/72_driver_tax_rates.sql. Chuyến ĐÃ
/// giao xong dùng số CHỐT thật (delivery.commissionAmount/vatAmount/pitAmount/driverPayout);
/// chuyến chưa giao xong chỉ ƯỚC TÍNH theo cấu hình hiện tại (số cuối có thể khác nếu admin đổi
/// tỷ lệ trước lúc giao xong).
class _PayoutBreakdownCard extends ConsumerWidget {
  final Delivery delivery;
  const _PayoutBreakdownCard({required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFinal = delivery.status == 'delivered';

    if (isFinal) {
      return _buildCard(
        context,
        estimated: false,
        commissionAmount: delivery.commissionAmount,
        vatAmount: delivery.vatAmount,
        pitAmount: delivery.pitAmount,
        payout: delivery.driverPayout,
        buyOnBehalfFeeShare: delivery.buyOnBehalfFeeShareAmount,
      );
    }

    final settingsAsync = ref.watch(driverFinanceSettingsProvider);
    return settingsAsync.when(
      loading: () => _buildCard(
        context,
        estimated: true,
        commissionAmount: 0,
        vatAmount: 0,
        pitAmount: 0,
        payout: delivery.driverFee,
        buyOnBehalfFeeShare: 0,
      ),
      error: (e, _) => _buildCard(
        context,
        estimated: true,
        commissionAmount: 0,
        vatAmount: 0,
        pitAmount: 0,
        payout: delivery.driverFee,
        buyOnBehalfFeeShare: 0,
      ),
      data: (settings) {
        final commissionAmount =
            (delivery.driverFee * settings.driverFeeCommissionRate / 100)
                .round();
        final vatAmount = (delivery.driverFee * settings.vatRate / 100).round();
        final pitAmount = (delivery.driverFee * settings.pitRate / 100).round();
        final payout =
            delivery.driverFee - commissionAmount - vatAmount - pitAmount;
        final buyOnBehalfFeeShare = delivery.isBuyOnBehalf
            ? (delivery.buyOnBehalfFee * settings.buyOnBehalfFeeShareRate / 100)
                  .round()
            : 0;
        return _buildCard(
          context,
          estimated: true,
          commissionAmount: commissionAmount,
          vatAmount: vatAmount,
          pitAmount: pitAmount,
          payout: payout,
          buyOnBehalfFeeShare: buyOnBehalfFeeShare,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool estimated,
    required int commissionAmount,
    required int vatAmount,
    required int pitAmount,
    required int payout,
    required int buyOnBehalfFeeShare,
  }) {
    final theme = Theme.of(context);
    final hasDeductions =
        commissionAmount > 0 || vatAmount > 0 || pitAmount > 0;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDeductions) ...[
              _payoutRow(context, 'Phí giao', formatVnd(delivery.driverFee)),
              if (commissionAmount > 0)
                _payoutRow(
                  context,
                  'Hoa hồng',
                  '-${formatVnd(commissionAmount)}',
                ),
              if (vatAmount > 0)
                _payoutRow(context, 'Thuế GTGT', '-${formatVnd(vatAmount)}'),
              if (pitAmount > 0)
                _payoutRow(context, 'Thuế TNCN', '-${formatVnd(pitAmount)}'),
              const Divider(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  estimated ? 'Dự kiến nhận được' : 'Bạn nhận được',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  formatVnd(payout),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (estimated)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Số cuối chốt lúc giao xong.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            // Riêng phần % phí mua hộ được chia (hofa-db/79_driver_buy_on_behalf_fee_share.sql)
            // — cộng thẳng ví thu nhập, KHÔNG nằm trong "Bạn nhận được" ở trên (đó là tiền công
            // chuyến giao, đã trừ hoa hồng/thuế) nên tách hẳn thành dòng riêng cho rõ.
            if (delivery.isBuyOnBehalf && buyOnBehalfFeeShare > 0) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phí mua hộ (bạn được chia)',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '+${formatVnd(buyOnBehalfFeeShare)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (estimated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Số cuối chốt lúc giao xong.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _payoutRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Mã đơn + danh sách món + tổng tiền — cho đơn thường (khác đơn mua hộ, đã có
/// _BuyOnBehalfShoppingCard riêng với ý nghĩa khác: tiền tài xế cần ứng mua giúp). Giúp tài xế
/// đối chiếu đúng đơn/đúng món khi giao mà không cần hỏi lại cửa hàng hay mở app khác.
class _OrderItemsCard extends StatelessWidget {
  final model.Order order;
  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đơn ${order.orderCode}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.productName}${item.variantName != null ? ' (${item.variantName})' : ''}'
                        '${item.toppings.isNotEmpty ? ' + ${item.toppings.map((t) => t.name).join(', ')}' : ''}'
                        '${item.note != null && item.note!.isNotEmpty ? ' — ${item.note}' : ''}',
                      ),
                    ),
                    Text(formatVnd(item.lineTotal)),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tổng tiền đơn', style: theme.textTheme.bodyMedium),
                Text(
                  formatVnd(order.totalAmount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Danh sách cần mua giúp khách — chỉ hiện cho đơn mua hộ, để tài xế biết chính xác cần mua gì
/// và mang đủ tiền trước khi đến quán (tiền hàng được hoàn ngay vào ví lúc xác nhận đã mua).
class _BuyOnBehalfShoppingCard extends StatelessWidget {
  final model.Order order;
  const _BuyOnBehalfShoppingCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cần mua giúp khách',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.productName}${item.variantName != null ? ' (${item.variantName})' : ''}'
                        '${item.toppings.isNotEmpty ? ' + ${item.toppings.map((t) => t.name).join(', ')}' : ''}'
                        '${item.note != null && item.note!.isNotEmpty ? ' — ${item.note}' : ''}',
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng tiền hàng cần ứng',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  formatVnd(order.subtotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Bạn ứng tiền mua tại quán, hoàn ngay vào ví khi bấm "Đã mua xong hàng" (kèm ảnh hoá đơn).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
