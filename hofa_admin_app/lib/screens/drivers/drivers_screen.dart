import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/driver.dart';
import '../../providers/admin_providers.dart';

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
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: d.isVerified
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.orange.withValues(alpha: 0.12),
                          child: Icon(d.isVerified ? Icons.verified_user : Icons.pending,
                              color: d.isVerified ? Colors.green : Colors.orange),
                        ),
                        title: Text('${d.vehicleType ?? "Xe"} · ${d.vehiclePlate ?? "—"}',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          '${d.totalDeliveries} chuyến · ${d.ratingAvg}★'
                          '${owing ? ' · Đang giữ ${formatVnd(-d.walletBalance)} tiền COD' : ''}',
                          style: TextStyle(color: owing ? theme.colorScheme.error : null),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(driverStatusLabels[d.status] ?? d.status),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            if (!d.isVerified)
                              FilledButton(
                                onPressed: _busy ? null : () => _verify(d),
                                child: const Text('Duyệt hồ sơ'),
                              )
                            else
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
