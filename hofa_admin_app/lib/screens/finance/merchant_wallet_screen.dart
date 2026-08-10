import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../models/merchant_wallet_summary.dart';
import '../../providers/admin_providers.dart';

/// "Ví cửa hàng" — số tổng toàn sàn + bảng từng cửa hàng, admin điều chỉnh tay ví (luôn có lý
/// do, xem hofa-db/64_merchant_wallet_ledger.sql, 65_merchant_wallet_withdrawals.sql). Mirror
/// DriverWalletScreen nhưng chỉ 1 ví (không tách COD/thu nhập, không có mức rủi ro — cửa hàng
/// không giữ tiền mặt hộ khách).
class MerchantWalletScreen extends ConsumerWidget {
  const MerchantWalletScreen({super.key});

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    MerchantWalletBalance merchant,
  ) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Điều chỉnh ví — ${merchant.name}'),
        content: SizedBox(
          width: dialogWidth(context, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          .adjustMerchantWallet(merchant.id, amount: amount, reason: reason);
      ref.invalidate(merchantWalletsProvider);
      ref.invalidate(merchantWalletSummaryProvider);
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
    final summaryAsync = ref.watch(merchantWalletSummaryProvider);
    final merchantsAsync = ref.watch(merchantWalletsProvider);

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
                label: 'Tổng số dư cửa hàng',
                value: formatVnd(s.totalBalance),
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
        Text('Từng cửa hàng', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Bấm vào 1 dòng để điều chỉnh tay ví (luôn kèm lý do, truy vết được).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        merchantsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Lỗi: $e'),
          data: (merchants) {
            if (merchants.isEmpty) {
              return const Text('Chưa có cửa hàng nào');
            }
            return Column(
              children: merchants.map((m) {
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _adjust(context, ref, m),
                    title: Text(m.name),
                    trailing: Text(
                      formatVnd(m.balance),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
