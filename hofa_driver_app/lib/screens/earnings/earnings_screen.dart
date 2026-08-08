import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/vietqr.dart';
import '../../models/earnings.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/driver_repository.dart';

final _earningsProvider = FutureProvider.autoDispose<Earnings>((ref) => DriverRepository().earnings());
final _driverRepo = DriverRepository();

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  Future<void> _deposit() async {
    final amountCtrl = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nạp tiền vào ví'),
        content: TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Số tiền muốn nạp (đ)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(amountCtrl.text.trim())),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0 || !mounted) return;

    try {
      final depositId = await _driverRepo.createDeposit(amount);
      final settings = await ref.read(bankAccountSettingsProvider.future);
      if (!mounted) return;
      if (!settings.isConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HOFA chưa cấu hình tài khoản ngân hàng — liên hệ hỗ trợ để nạp tiền.')),
        );
        return;
      }
      final qrUrl = buildVietQrUrl(
        bankBin: settings.bankBin!,
        accountNumber: settings.accountNumber!,
        amount: amount,
        addInfo: 'NAP-${depositId.substring(0, 8).toUpperCase()}',
        accountName: settings.accountHolderName,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Quét mã để nạp tiền'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(qrUrl, width: 240, height: 240, fit: BoxFit.contain),
                ),
                const SizedBox(height: 12),
                Text('${settings.bankName ?? ''} · ${settings.accountNumber}'),
                if (settings.accountHolderName != null) Text(settings.accountHolderName!),
                const SizedBox(height: 8),
                Text(
                  'Số tiền: ${formatVnd(amount)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'HOFA sẽ cộng tiền vào ví ngay sau khi xác nhận đã nhận được chuyển khoản.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Đã hiểu')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _withdraw(int currentBalance) async {
    final amountCtrl = TextEditingController();
    final settings = await ref.read(bankAccountSettingsProvider.future);
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rút tiền'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Số dư hiện tại: ${formatVnd(currentBalance)}'),
            Text('Số dư tối thiểu sau khi rút: ${formatVnd(settings.minWithdrawalBalance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tiền muốn rút (đ)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gửi yêu cầu')),
        ],
      ),
    );
    final amount = int.tryParse(amountCtrl.text.trim());
    if (ok != true || amount == null || amount <= 0 || !mounted) return;

    try {
      await _driverRepo.createWithdrawal(amount);
      ref.invalidate(_earningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi yêu cầu rút tiền — HOFA sẽ chuyển khoản sớm.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final earningsAsync = ref.watch(_earningsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Thu nhập')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_earningsProvider),
        child: earningsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (earnings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Số dư ví', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(formatVnd(earnings.walletBalance),
                          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        earnings.walletBalance < 0
                            ? 'Số âm là tiền COD bạn đang giữ hộ, cần nộp lại cho HOFA'
                            : 'Có thể rút về tài khoản ngân hàng',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _deposit,
                              icon: const Icon(Icons.add_card_outlined),
                              label: const Text('Nạp tiền'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _withdraw(earnings.walletBalance),
                              icon: const Icon(Icons.savings_outlined),
                              label: const Text('Rút tiền'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(label: 'Hôm nay', value: formatVnd(earnings.todayTotal)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(label: 'Tổng chuyến', value: '${earnings.totalDeliveries}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(label: 'Đánh giá', value: '${earnings.ratingAvg}★ (${earnings.ratingCount} lượt)'),
              const SizedBox(height: 24),
              Text('Chuyến gần đây', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (earnings.recentDeliveries.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Chưa có chuyến nào'))
              else
                ...earnings.recentDeliveries.map((d) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(formatVnd(d.driverFee)),
                        subtitle: Text(d.deliveredAt != null ? formatDateTime(d.deliveredAt!) : '—'),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

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
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
