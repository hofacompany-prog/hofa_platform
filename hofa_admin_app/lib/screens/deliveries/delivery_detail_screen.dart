import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/admin_delivery.dart';
import '../../providers/admin_providers.dart';
import '../merchants/location_picker_screen.dart';
import '../../core/responsive.dart';

/// Chi tiết 1 chuyến giao hàng — cho admin xem đầy đủ + SỬA điểm lấy hàng (dữ liệu của chi
/// nhánh, qua updateBranch) và điểm giao hàng (dữ liệu riêng của đơn, qua
/// updateOrderShipping) TRỰC TIẾP TRÊN BẢN ĐỒ (dùng chung LocationPickerScreen với màn chọn vị
/// trí chi nhánh lúc tạo cửa hàng) khi toạ độ/địa chỉ sai hoặc thiếu, cùng đổi trạng thái/xoá
/// như ở màn danh sách "Chuyến giao hàng" (deliveries_screen.dart) cho tiện thao tác tại chỗ.
class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<DeliveryDetailScreen> createState() =>
      _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  bool _busy = false;

  Future<void> _editPickup(AdminDelivery d) async {
    if (d.branchId == null) return;
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: d.branchLatitude,
          initialLongitude: d.branchLongitude,
        ),
      ),
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateBranch(d.branchId!, {
        'line1': picked.line1,
        'ward': picked.ward,
        'district': picked.district,
        'province': picked.province,
        'latitude': picked.latitude,
        'longitude': picked.longitude,
      });
      ref.invalidate(deliveryDetailProvider(widget.deliveryId));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu điểm lấy hàng')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDropoff(AdminDelivery d) async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: d.shipLatitude,
          initialLongitude: d.shipLongitude,
        ),
      ),
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateOrderShipping(d.orderId, {
        'ship_line1': picked.line1,
        'ship_ward': picked.ward,
        'ship_district': picked.district,
        'ship_province': picked.province,
        'ship_latitude': picked.latitude,
        'ship_longitude': picked.longitude,
      });
      ref.invalidate(deliveryDetailProvider(widget.deliveryId));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu điểm giao hàng')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceStatus(AdminDelivery d) async {
    var selected = d.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Chuyển trạng thái chuyến giao hàng'),
          content: SizedBox(
            width: dialogWidth(context, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chỉ đổi đúng cột trạng thái, không đụng tồn kho hay ví tài xế.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: deliveryStatusLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setInner(() => selected = v ?? selected),
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
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).forceDeliveryStatus(d.id, selected);
      ref.invalidate(deliveryDetailProvider(widget.deliveryId));
      ref.invalidate(deliveriesProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AdminDelivery d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá chuyến giao hàng?'),
        content: Text(
          'Chuyến của đơn ${d.orderCode} sẽ bị xoá vĩnh viễn, không thể khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).deleteDelivery(d.id);
      ref.invalidate(deliveriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xoá chuyến của đơn ${d.orderCode}')),
        );
        context.go('/drivers?tab=1');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deliveryAsync = ref.watch(deliveryDetailProvider(widget.deliveryId));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết chuyến giao hàng')),
      body: deliveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (d) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: LinearProgressIndicator(),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${d.orderCode} · ${d.merchantName ?? ""}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(deliveryStatusLabels[d.status] ?? d.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tài xế: ${d.driverName ?? "chưa gán"}${d.driverPhone != null ? " (${d.driverPhone})" : ""}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _PointCard(
                    icon: Icons.storefront,
                    iconColor: theme.colorScheme.primary,
                    title: 'Điểm lấy hàng',
                    name: d.branchName ?? '—',
                    phone: d.branchPhone,
                    address: d.branchFullAddress,
                    latitude: d.branchLatitude,
                    longitude: d.branchLongitude,
                    onEdit: d.branchId == null ? null : () => _editPickup(d),
                  ),
                  const SizedBox(height: 12),
                  _PointCard(
                    icon: Icons.flag,
                    iconColor: theme.colorScheme.secondary,
                    title: 'Điểm giao hàng',
                    name: d.customerName ?? '—',
                    phone: d.customerPhone,
                    address: d.shipFullAddress,
                    latitude: d.shipLatitude,
                    longitude: d.shipLongitude,
                    onEdit: () => _editDropoff(d),
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
                          _infoRow(
                            'Khoảng cách',
                            d.distanceKm != null
                                ? '${d.distanceKm!.toStringAsFixed(1)} km'
                                : '—',
                          ),
                          _infoRow(
                            'Thời gian dự kiến',
                            d.etaMinutes != null ? '${d.etaMinutes} phút' : '—',
                          ),
                          _infoRow('Phí cho tài xế', formatVnd(d.driverFee)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _forceStatus(d),
                    icon: const Icon(Icons.edit),
                    label: const Text('Chuyển trạng thái thủ công'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _delete(d),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xoá chuyến giao hàng'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _PointCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String name;
  final String? phone;
  final String address;
  final double? latitude;
  final double? longitude;
  final VoidCallback? onEdit;

  const _PointCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.name,
    this.phone,
    required this.address,
    this.latitude,
    this.longitude,
    required this.onEdit,
  });

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
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Sửa'),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (phone != null && phone!.isNotEmpty) Text(phone!),
                  Text(address.isEmpty ? 'Chưa có địa chỉ' : address),
                  Text(
                    latitude != null && longitude != null
                        ? 'Toạ độ: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                        : 'Chưa có toạ độ',
                    style: TextStyle(
                      color: latitude == null
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
