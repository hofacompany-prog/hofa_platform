import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/driver.dart';
import '../../providers/admin_providers.dart';

const _rejectionReasonPresets = [
  'Giấy tờ mờ/không rõ',
  'Thông tin không khớp giấy tờ',
  'Thiếu ảnh giấy tờ',
  'Thông tin ngân hàng không hợp lệ',
  'Khác',
];

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen> {
  bool _busy = false;
  bool _onlyUnverified = false;

  Future<void> _verify(Driver d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duyệt hồ sơ tài xế?'),
        content: Text(
          'Xác nhận giấy tờ của tài xế này là hợp lệ.\n\n'
          'CMND/CCCD: ${d.nationalId ?? "—"}\n'
          'Bằng lái: ${d.licenseNo ?? "—"}\n'
          'Xe: ${d.vehicleType ?? "—"} · ${d.vehiclePlate ?? "—"}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Duyệt')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).verifyDriver(d.id);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Driver d) async {
    var reason = _rejectionReasonPresets.first;
    final customCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Từ chối hồ sơ tài xế?'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tài xế sẽ nhận được thông báo kèm lý do, sửa/nộp lại hồ sơ để được xét duyệt tiếp.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Lý do', border: OutlineInputBorder(), isDense: true),
                  items: _rejectionReasonPresets.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setInner(() => reason = v ?? reason),
                ),
                if (reason == 'Khác') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Ghi rõ lý do', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Từ chối'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final finalReason = reason == 'Khác' ? customCtrl.text.trim() : reason;
    if (finalReason.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).rejectDriver(d.id, finalReason);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Gỡ tài xế kẹt ở 1 trạng thái (thường 'busy') không tự nhận được chuyến mới — vd chuyến cũ
  /// bị xoá/đổi trạng thái ở màn "Chuyến giao hàng" nhưng vì lý do gì đó tài xế không tự về lại
  /// 'online'. Chỉ đổi đúng cột status của drivers, không đụng gì tới deliveries.
  Future<void> _changeStatus(Driver d) async {
    var selected = d.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Đổi trạng thái tài xế'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dùng khi tài xế bị kẹt trạng thái (vd "Đang giao" mãi) và không nhận được chuyến mới.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: driverStatusLabels.entries
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
      await ref.read(adminRepoProvider).forceDriverStatus(d.id, selected);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driversProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài xế'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(driversProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Chỉ hiện hồ sơ chưa duyệt'),
                  selected: _onlyUnverified,
                  onSelected: (v) => setState(() => _onlyUnverified = v),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: driversAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final list = _onlyUnverified ? all.where((d) => !d.isVerified).toList() : all;
                if (list.isEmpty) {
                  return Center(child: Text(_onlyUnverified ? 'Không có hồ sơ nào chờ duyệt' : 'Chưa có tài xế nào'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = list[i];
                    // Ví âm nghĩa là tài xế đang giữ tiền COD chưa nộp về (xem HUONG_DAN.md)
                    final owing = d.walletBalance < 0;
                    final verification = driverVerificationState(d);
                    final (statusIcon, statusColor) = switch (verification) {
                      DriverVerificationState.verified => (Icons.verified_user, Colors.green),
                      DriverVerificationState.rejected => (Icons.block, theme.colorScheme.error),
                      DriverVerificationState.pending => (Icons.pending, Colors.orange),
                    };
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Tooltip(
                          message: verification == DriverVerificationState.rejected
                              ? 'Bị từ chối: ${d.rejectionReason ?? ""}'
                              : '',
                          child: CircleAvatar(
                            backgroundColor: statusColor.withValues(alpha: 0.12),
                            child: Icon(statusIcon, color: statusColor),
                          ),
                        ),
                        title: Text('${d.vehicleType ?? "Xe"} · ${d.vehiclePlate ?? "—"}',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          '${d.totalDeliveries} chuyến · ${d.ratingAvg}★'
                          '${owing ? ' · Đang giữ ${formatVnd(-d.walletBalance)} tiền COD' : ''}'
                          '${verification == DriverVerificationState.rejected ? ' · Bị từ chối: ${d.rejectionReason ?? ""}' : ''}',
                          style: TextStyle(color: owing || verification == DriverVerificationState.rejected ? theme.colorScheme.error : null),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ActionChip(
                              label: Text(driverStatusLabels[d.status] ?? d.status),
                              visualDensity: VisualDensity.compact,
                              onPressed: _busy ? null : () => _changeStatus(d),
                            ),
                            const SizedBox(width: 8),
                            if (!d.isVerified) ...[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                onPressed: _busy ? null : () => _reject(d),
                                child: const Text('Từ chối'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _busy ? null : () => _verify(d),
                                child: const Text('Duyệt hồ sơ'),
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('Đã duyệt', style: TextStyle(color: Colors.green)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
