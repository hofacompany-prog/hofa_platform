import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../models/driver.dart';
import '../../providers/admin_providers.dart';

/// "Quản lý tiền tài xế" — số tổng toàn sàn + bảng từng tài xế (Ví trên, Ví thu nhập), admin
/// điều chỉnh tay ví (luôn có lý do) — xem hofa-db/69_driver_wallet_vi_tren.sql.
class DriverWalletScreen extends ConsumerWidget {
  const DriverWalletScreen({super.key});

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    Driver driver,
  ) async {
    String wallet = 'earning';
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text('Điều chỉnh ví — ${driver.vehiclePlate ?? driver.id}'),
          content: SizedBox(
            width: dialogWidth(context, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'earning', label: Text('Ví thu nhập')),
                    ButtonSegment(value: 'cod', label: Text('Ví trên')),
                  ],
                  selected: {wallet},
                  onSelectionChanged: (s) => setInner(() => wallet = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Số tiền (âm để trừ)',
                    helperText: 'Vd: 50000 để cộng, -50000 để trừ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lý do (bắt buộc)',
                  ),
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
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    final amount = int.tryParse(amountCtrl.text.trim());
    final reason = reasonCtrl.text.trim();
    if (ok != true ||
        amount == null ||
        amount == 0 ||
        reason.isEmpty ||
        !context.mounted)
      return;

    try {
      await ref
          .read(adminRepoProvider)
          .adjustDriverWallet(
            driver.id,
            wallet: wallet,
            amount: amount,
            reason: reason,
          );
      ref.invalidate(driversProvider);
      ref.invalidate(driverWalletSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã điều chỉnh ví')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(driverWalletSummaryProvider);
    final driversAsync = ref.watch(driversProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Tổng quan', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        summaryAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Lỗi: $e'),
          data: (s) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(
                label: 'Tổng Ví trên',
                value: formatVnd(s.codHeld),
                color: theme.colorScheme.secondary,
              ),
              _SummaryCard(
                label: 'Thu nhập tài xế',
                value: formatVnd(s.earningTotal),
                color: theme.colorScheme.primary,
              ),
              _SummaryCard(
                label: 'Chờ rút',
                value: formatVnd(s.pendingWithdrawals),
                color: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Từng tài xế', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Bấm vào 1 dòng để điều chỉnh tay ví (luôn kèm lý do, truy vết được).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        driversAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Lỗi: $e'),
          data: (drivers) {
            if (drivers.isEmpty) {
              return const Text('Chưa có tài xế nào');
            }
            return Column(
              children: drivers.map((d) {
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _adjust(context, ref, d),
                    title: Text(
                      '${d.vehicleType ?? "Xe"} · ${d.vehiclePlate ?? d.id}',
                    ),
                    subtitle: Text(
                      'Ví trên: ${formatVnd(d.codBalance)} · Có thể rút: ${formatVnd(d.earningBalance)}',
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
