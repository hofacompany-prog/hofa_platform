import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/delivery.dart';
import '../../models/order.dart' as model;
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';
import '../../widgets/image_upload_field.dart';

const _stageOrder = ['accepted', 'arrived_store', 'picked_up', 'delivering', 'delivered'];

class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  final _repo = DeliveryRepository();
  bool _busy = false;
  bool _loadingContext = false;
  model.Order? _order;
  Branch? _branch;

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

  Future<void> _advance(String nextStatus, {String? otp, String? recipientName, List<String>? proofPhotoUrls, String? failureReason}) async {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
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
              TextField(
                controller: otpCtrl,
                decoration: const InputDecoration(labelText: 'Mã OTP khách đọc cho bạn'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Người nhận (không bắt buộc)'),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true || otpCtrl.text.trim().isEmpty) return;
    await _advance(
      'delivered',
      otp: otpCtrl.text.trim(),
      recipientName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      proofPhotoUrls: photoUrl != null ? [photoUrl!] : null,
    );
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
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

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final deliveryAsync = ref.watch(deliveryProvider(widget.deliveryId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Chuyến giao hàng')),
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
                          Icon(Icons.storefront, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(branch?.name ?? 'Đang tải...', style: theme.textTheme.titleSmall)),
                          if (branch != null)
                            IconButton(icon: const Icon(Icons.directions), onPressed: () => _navigate(branch.latitude, branch.longitude)),
                          if (branch?.phone != null)
                            IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _call(branch!.phone!)),
                        ],
                      ),
                      if (branch != null) Padding(padding: const EdgeInsets.only(left: 32), child: Text(branch.fullLine)),
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
                          Expanded(child: Text(order?.shipRecipientName ?? 'Đang tải...', style: theme.textTheme.titleSmall)),
                          if (order != null && order.shipLatitude != null)
                            IconButton(
                                icon: const Icon(Icons.directions),
                                onPressed: () => _navigate(order.shipLatitude!, order.shipLongitude!)),
                          if (order != null) IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _call(order.shipRecipientPhone)),
                        ],
                      ),
                      if (order != null) Padding(padding: const EdgeInsets.only(left: 32), child: Text(order.shipFullAddress)),
                      if (order?.shipNote != null && order!.shipNote!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 32, top: 4),
                          child: Text('Ghi chú: ${order.shipNote}', style: theme.textTheme.bodySmall),
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bạn nhận được', style: theme.textTheme.bodyMedium),
                      Text(formatVnd(delivery.driverFee), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              if (order != null && order.paymentMethod == 'cod')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Thu hộ khách: ${formatVnd(order.totalAmount)} (COD)',
                      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 24),
              _ActionArea(
                status: delivery.status,
                failureReason: delivery.failureReason,
                busy: _busy,
                onArrivedStore: () => _advance('arrived_store'),
                onPickedUp: () => _promptOtp('Nhập mã OTP lấy hàng (cửa hàng đọc cho bạn)', 'picked_up'),
                onStartDelivering: () => _advance('delivering'),
                onDelivered: _promptDelivered,
                onFailed: _promptFailed,
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
    final currentIndex = failed ? _stageOrder.length : _stageOrder.indexOf(status);

    return Row(
      children: [
        for (var i = 0; i < _stageOrder.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: i <= currentIndex
                      ? (failed ? theme.colorScheme.error : theme.colorScheme.primary)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: i < currentIndex || (i == currentIndex && !failed)
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(deliveryStatusLabels[_stageOrder[i]]!.split(' ').first, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
              ],
            ),
          ),
          if (i != _stageOrder.length - 1)
            Expanded(
              child: Container(height: 2, color: i < currentIndex ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest),
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
  final VoidCallback onArrivedStore;
  final VoidCallback onPickedUp;
  final VoidCallback onStartDelivering;
  final VoidCallback onDelivered;
  final VoidCallback onFailed;
  final VoidCallback onDone;

  const _ActionArea({
    required this.status,
    required this.failureReason,
    required this.busy,
    required this.onArrivedStore,
    required this.onPickedUp,
    required this.onStartDelivering,
    required this.onDelivered,
    required this.onFailed,
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
          label: const Text('Đã đến quán lấy hàng'),
        );
      case 'arrived_store':
        return FilledButton.icon(
          onPressed: busy ? null : onPickedUp,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Đã lấy hàng'),
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
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.error_outline),
              label: const Text('Báo giao thất bại'),
            ),
          ],
        );
      case 'delivered':
        return Column(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 48),
            const SizedBox(height: 8),
            Text('Đã giao hàng thành công', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: const Text('Về trang chủ')),
          ],
        );
      case 'failed':
        return Column(
          children: [
            Icon(Icons.cancel_outlined, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 8),
            Text('Giao thất bại${failureReason != null ? ': $failureReason' : ''}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: const Text('Về trang chủ')),
          ],
        );
      default:
        return const SizedBox();
    }
  }
}
