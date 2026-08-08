import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/admin_delivery.dart';
import '../../providers/admin_providers.dart';

/// Chi tiết 1 chuyến giao hàng — cho admin xem đầy đủ + SỬA điểm lấy hàng (dữ liệu của chi
/// nhánh, qua updateBranch) và điểm giao hàng (dữ liệu riêng của đơn, qua
/// updateOrderShipping) khi toạ độ/địa chỉ sai hoặc thiếu, cùng đổi trạng thái/xoá như ở màn
/// danh sách "Chuyến giao hàng" (deliveries_screen.dart) cho tiện thao tác tại chỗ.
class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  bool _busy = false;

  Future<void> _editPickup(AdminDelivery d) async {
    if (d.branchId == null) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditPointDialog(
        title: 'Sửa điểm lấy hàng',
        line1: d.branchLine1 ?? '',
        ward: d.branchWard ?? '',
        district: d.branchDistrict ?? '',
        province: d.branchProvince ?? '',
        latitude: d.branchLatitude,
        longitude: d.branchLongitude,
      ),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateBranch(d.branchId!, result);
      ref.invalidate(deliveryDetailProvider(widget.deliveryId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu điểm lấy hàng')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDropoff(AdminDelivery d) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditPointDialog(
        title: 'Sửa điểm giao hàng',
        line1: d.shipLine1 ?? '',
        ward: d.shipWard ?? '',
        district: d.shipDistrict ?? '',
        province: d.shipProvince ?? '',
        latitude: d.shipLatitude,
        longitude: d.shipLongitude,
        fieldPrefix: 'ship_',
      ),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateOrderShipping(d.orderId, result);
      ref.invalidate(deliveryDetailProvider(widget.deliveryId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu điểm giao hàng')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chỉ đổi đúng cột trạng thái, không đụng tồn kho hay ví tài xế.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: deliveryStatusLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setInner(() => selected = v ?? selected),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AdminDelivery d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá chuyến giao hàng?'),
        content: Text('Chuyến của đơn ${d.orderCode} sẽ bị xoá vĩnh viễn, không thể khôi phục.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xoá chuyến của đơn ${d.orderCode}')));
        context.go('/deliveries');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
                  if (_busy) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${d.orderCode} · ${d.merchantName ?? ""}',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Chip(label: Text(deliveryStatusLabels[d.status] ?? d.status)),
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
                          _infoRow('Khoảng cách', d.distanceKm != null ? '${d.distanceKm!.toStringAsFixed(1)} km' : '—'),
                          _infoRow('Thời gian dự kiến', d.etaMinutes != null ? '${d.etaMinutes} phút' : '—'),
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
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
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
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
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
                if (onEdit != null) TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 16), label: const Text('Sửa')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (phone != null && phone!.isNotEmpty) Text(phone!),
                  Text(address.isEmpty ? 'Chưa có địa chỉ' : address),
                  Text(
                    latitude != null && longitude != null
                        ? 'Toạ độ: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                        : 'Chưa có toạ độ',
                    style: TextStyle(
                      color: latitude == null ? theme.colorScheme.error : theme.colorScheme.outline,
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

/// Hộp thoại sửa 1 điểm (địa chỉ + toạ độ) — dùng chung cho cả điểm lấy hàng lẫn giao hàng, trả
/// về Map đúng tên cột đích (branches.* hay orders.ship_*, xem [fieldPrefix]) để gọi thẳng
/// updateBranch()/updateOrderShipping() mà không cần đổi tên field ở nơi gọi.
class _EditPointDialog extends StatefulWidget {
  final String title;
  final String line1;
  final String ward;
  final String district;
  final String province;
  final double? latitude;
  final double? longitude;
  final String fieldPrefix;

  const _EditPointDialog({
    required this.title,
    required this.line1,
    required this.ward,
    required this.district,
    required this.province,
    required this.latitude,
    required this.longitude,
    this.fieldPrefix = '',
  });

  @override
  State<_EditPointDialog> createState() => _EditPointDialogState();
}

class _EditPointDialogState extends State<_EditPointDialog> {
  late final _line1Ctrl = TextEditingController(text: widget.line1);
  late final _wardCtrl = TextEditingController(text: widget.ward);
  late final _districtCtrl = TextEditingController(text: widget.district);
  late final _provinceCtrl = TextEditingController(text: widget.province);
  late final _latCtrl = TextEditingController(text: widget.latitude?.toString() ?? '');
  late final _lngCtrl = TextEditingController(text: widget.longitude?.toString() ?? '');

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _wardCtrl.dispose();
    _districtCtrl.dispose();
    _provinceCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    Navigator.pop(context, {
      '${widget.fieldPrefix}line1': _line1Ctrl.text.trim(),
      '${widget.fieldPrefix}ward': _wardCtrl.text.trim(),
      '${widget.fieldPrefix}district': _districtCtrl.text.trim(),
      '${widget.fieldPrefix}province': _provinceCtrl.text.trim(),
      '${widget.fieldPrefix}latitude': lat,
      '${widget.fieldPrefix}longitude': lng,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _line1Ctrl, decoration: const InputDecoration(labelText: 'Địa chỉ (số nhà, đường)')),
              const SizedBox(height: 8),
              TextField(controller: _wardCtrl, decoration: const InputDecoration(labelText: 'Phường/Xã')),
              const SizedBox(height: 8),
              TextField(controller: _districtCtrl, decoration: const InputDecoration(labelText: 'Quận/Huyện')),
              const SizedBox(height: 8),
              TextField(controller: _provinceCtrl, decoration: const InputDecoration(labelText: 'Tỉnh/Thành phố')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latCtrl,
                      decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      decoration: const InputDecoration(labelText: 'Kinh độ (longitude)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Mẹo: mở Google Maps, giữ tay trên vị trí đúng rồi bấm vào toạ độ hiện ra để sao chép.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}
