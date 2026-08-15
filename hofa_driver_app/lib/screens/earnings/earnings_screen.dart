import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/vietqr.dart';
import '../../models/earnings.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/driver_repository.dart';

final earningsProvider = FutureProvider.autoDispose<Earnings>(
  (ref) => DriverRepository().earnings(),
);
final _driverRepo = DriverRepository();

/// Thu nhập — 2 ví riêng (xem hofa-db/69_driver_wallet_vi_tren.sql): **Ví trên** (vốn để chạy
/// đơn — phải nạp trước, trừ tự động khi giao đơn xong, KHÔNG rút/chuyển đi đâu được) và **Ví
/// thu nhập** (tiền thật, rút được về ngân hàng). Nạp tiền luôn cộng vào Ví trên và là hành động
/// quan trọng nhất để tiếp tục nhận đơn — đặt lên đầu màn hình.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  /// Nạp thẳng vào Ví trên (chuyển khoản cho HOFA, admin xác nhận). Cần cho tài xế mới/tài xế
  /// thiếu vốn: hệ thống chỉ gán đơn khi cod_balance (Ví trên) > giá trị đơn (xem
  /// server/src/dispatch.js), nên không đủ vốn là không nhận được đơn nào, kể cả đơn đầu tiên.
  Future<void> _deposit() async {
    final amountCtrl = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nạp tiền vào Ví trên'),
        content: TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Số tiền muốn nạp (đ)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(amountCtrl.text.trim())),
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
          const SnackBar(
            content: Text(
              'HOFA chưa cấu hình tài khoản ngân hàng — liên hệ hỗ trợ để nạp tiền.',
            ),
          ),
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
                  child: Image.network(
                    qrUrl,
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text('${settings.bankName ?? ''} · ${settings.accountNumber}'),
                if (settings.accountHolderName != null)
                  Text(settings.accountHolderName!),
                const SizedBox(height: 8),
                Text(
                  'Số tiền: ${formatVnd(amount)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'HOFA sẽ cộng tiền vào Ví trên ngay sau khi xác nhận đã nhận được chuyển khoản.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _withdraw(int earningBalance) async {
    final settings = await ref.read(driverFinanceSettingsProvider.future);
    final minWithdrawal = settings.minWithdrawalAmount;
    if (!mounted) return;

    final amountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rút tiền'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Số dư khả dụng: ${formatVnd(earningBalance)}'),
            if (minWithdrawal > 0) ...[
              const SizedBox(height: 4),
              Text('Rút tối thiểu: ${formatVnd(minWithdrawal)}'),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền muốn rút (đ)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    final amount = int.tryParse(amountCtrl.text.trim());
    if (ok != true || amount == null || amount <= 0 || !mounted) return;
    if (amount < minWithdrawal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Số tiền rút tối thiểu là ${formatVnd(minWithdrawal)}'),
        ),
      );
      return;
    }

    try {
      await _driverRepo.createWithdrawal(amount);
      ref.invalidate(earningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã gửi yêu cầu rút tiền — HOFA sẽ chuyển khoản sớm.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  /// Chuyển nội bộ 1 chiều Ví thu nhập → Ví trên — tự động ngay, không cần admin duyệt (khác
  /// hẳn "Nạp tiền"/"Rút tiền" thật qua ngân hàng ở trên).
  Future<void> _transferToViTren(int earningBalance) async {
    final amountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nạp vào Ví trên'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Số dư Ví thu nhập: ${formatVnd(earningBalance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền muốn chuyển (đ)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chuyển ngay'),
          ),
        ],
      ),
    );
    final amount = int.tryParse(amountCtrl.text.trim());
    if (ok != true || amount == null || amount <= 0 || !mounted) return;

    try {
      await _driverRepo.transferEarningToViTren(amount);
      ref.invalidate(earningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã chuyển vào Ví trên')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final earningsAsync = ref.watch(earningsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thu nhập'),
        actions: [
          IconButton(
            tooltip: 'Lịch sử ví',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/wallet/history'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(earningsProvider),
        child: earningsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (earnings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Nạp tiền — nổi bật, đặt đầu tiên vì đây là hành động quan trọng nhất để tiếp
              // tục nhận được đơn (Ví trên hết vốn thì hệ thống ngừng gán đơn mới).
              Card(
                elevation: 0,
                color: theme.colorScheme.primary,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nạp tiền vào Ví trên',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cần đủ Ví trên mới nhận được đơn mới — nạp ngay để tiếp tục chạy đơn.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _deposit,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.onPrimary,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                          icon: const Icon(Icons.add_card_outlined),
                          label: const Text('Nạp tiền'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.5,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ví trên', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        formatVnd(earnings.codBalance),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vốn để nhận đơn mới — tự động trừ khi giao đơn xong, không rút/chuyển '
                        'đi đâu được.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ví thu nhập', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        formatVnd(earnings.earningBalance),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tiền thật, rút được về tài khoản ngân hàng.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _withdraw(earnings.earningBalance),
                              icon: const Icon(Icons.savings_outlined),
                              label: const Text('Rút tiền'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _transferToViTren(earnings.earningBalance),
                              icon: const Icon(Icons.arrow_upward),
                              label: const Text('Nạp vào Ví trên'),
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
                    child: _StatCard(
                      label: 'Hôm nay',
                      value: formatVnd(earnings.today.net),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Tổng chuyến',
                      value: '${earnings.totalDeliveries}',
                    ),
                  ),
                ],
              ),
              if (earnings.today.commissionAmount > 0 ||
                  earnings.today.vatAmount > 0 ||
                  earnings.today.pitAmount > 0 ||
                  earnings.today.buyOnBehalfFeeShareAmount > 0) ...[
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        _financeRow(
                          context,
                          'Phí giao hôm nay',
                          formatVnd(earnings.today.gross),
                        ),
                        if (earnings.today.commissionAmount > 0)
                          _financeRow(
                            context,
                            'Hoa hồng',
                            '-${formatVnd(earnings.today.commissionAmount)}',
                          ),
                        if (earnings.today.vatAmount > 0)
                          _financeRow(
                            context,
                            'Thuế GTGT',
                            '-${formatVnd(earnings.today.vatAmount)}',
                          ),
                        if (earnings.today.pitAmount > 0)
                          _financeRow(
                            context,
                            'Thuế TNCN',
                            '-${formatVnd(earnings.today.pitAmount)}',
                          ),
                        const Divider(height: 1),
                        _financeRow(
                          context,
                          'Thực nhận hôm nay',
                          formatVnd(earnings.today.net),
                          bold: true,
                        ),
                        // Riêng % phí mua hộ được chia (hofa-db/79_driver_buy_on_behalf_fee_share.sql)
                        // — cộng thẳng ví thu nhập, không nằm trong "Thực nhận hôm nay" ở trên
                        // (đó là tiền công chuyến giao, đã trừ hoa hồng/thuế).
                        if (earnings.today.buyOnBehalfFeeShareAmount > 0) ...[
                          const Divider(height: 1),
                          _financeRow(
                            context,
                            'Phí mua hộ được chia',
                            '+${formatVnd(earnings.today.buyOnBehalfFeeShareAmount)}',
                            bold: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _StatCard(
                label: 'Đánh giá',
                value: '${earnings.ratingAvg}★ (${earnings.ratingCount} lượt)',
              ),
              const SizedBox(height: 24),
              Text('Chuyến gần đây', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (earnings.recentDeliveries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chưa có chuyến nào'),
                )
              else
                ...earnings.recentDeliveries.map(
                  (d) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(
                        '${d.orderCode} · ${formatVnd(d.driverPayout)}',
                      ),
                      subtitle: Text(
                        d.deliveredAt != null
                            ? formatDateTime(d.deliveredAt!)
                            : '—',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _financeRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
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
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
