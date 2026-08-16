import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/vietqr.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/bank.dart';
import '../../models/bank_account_settings.dart';
import '../../models/driver_wallet_request.dart';
import '../../models/merchant_wallet_request.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import '../../core/responsive.dart';

/// 6 tab dưới 1 màn "Thanh toán" — tách nhỏ để mỗi tab không bị quá tải:
/// Cấu hình (tài khoản ngân hàng của sàn), Đơn hàng (chờ xác nhận thanh toán chuyển khoản),
/// Tài xế nạp tiền (nạp thẳng vào Ví trên — tài xế phải có cod_balance (Ví trên) > giá trị đơn
/// mới được gán đơn, xem hofa-db/69_driver_wallet_vi_tren.sql) / Tài xế rút tiền (duyệt ví tài
/// xế, chỉ đụng Ví thu nhập), Cửa hàng rút tiền (duyệt ví cửa hàng — xem
/// hofa-db/65_merchant_wallet_withdrawals.sql, không có QR như tài xế vì merchants chưa thu
/// thập mã BIN ngân hàng), Ngân hàng (danh sách cho dropdown ở app tài xế lúc đăng ký/sửa hồ
/// sơ). Không còn tab "Đối soát COD" — Ví trên đổi vai trò thành vốn, không còn khái niệm "tiền
/// COD nợ cần nộp lại" (xem hofa-db/69_driver_wallet_vi_tren.sql).
class PaymentSettingsScreen extends StatelessWidget {
  const PaymentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thanh toán'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Cấu hình'),
              Tab(text: 'Đơn hàng'),
              Tab(text: 'Tài xế nạp tiền'),
              Tab(text: 'Tài xế rút tiền'),
              Tab(text: 'Cửa hàng rút tiền'),
              Tab(text: 'Ngân hàng'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ConfigTab(),
            _PendingOrdersTab(),
            _WalletDepositsTab(),
            _WalletWithdrawalsTab(),
            _MerchantWithdrawalsTab(),
            _BanksTab(),
          ],
        ),
      ),
    );
  }
}

class _ConfigTab extends ConsumerStatefulWidget {
  const _ConfigTab();

  @override
  ConsumerState<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<_ConfigTab> {
  final _bankNameCtrl = TextEditingController();
  final _bankBinCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _minWithdrawalCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankBinCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    _minWithdrawalCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(BankAccountSettings s) {
    _bankNameCtrl.text = s.bankName ?? '';
    _bankBinCtrl.text = s.bankBin ?? '';
    _accountNumberCtrl.text = s.accountNumber ?? '';
    _accountHolderCtrl.text = s.accountHolderName ?? '';
    _minWithdrawalCtrl.text = VndInputFormatter.display(s.minWithdrawalBalance);
  }

  Future<void> _save(String? id) async {
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateBankAccountSettings(
            BankAccountSettings(
              id: id,
              bankName: _bankNameCtrl.text.trim(),
              bankBin: _bankBinCtrl.text.trim(),
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolderName: _accountHolderCtrl.text.trim(),
              minWithdrawalBalance:
                  VndInputFormatter.parse(_minWithdrawalCtrl.text) ?? 0,
            ),
          );
      ref.invalidate(bankAccountSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông tin ngân hàng')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(bankAccountSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (settings) {
        if (!_initialized) {
          _fillFrom(settings);
          _initialized = true;
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thông tin tài khoản ngân hàng',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dùng để tạo mã VietQR cho khách quét chuyển khoản khi đặt hàng bằng '
                    'phương thức "Chuyển khoản ngân hàng", và để tài xế nạp tiền vào ví. Miễn '
                    'phí, không cần tài khoản/API của cổng thanh toán nào.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _bankNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tên ngân hàng',
                              helperText: 'Vd: Vietcombank, Techcombank...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _bankBinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Mã ngân hàng (BIN chuẩn VietQR)',
                              helperText:
                                  'Tra mã BIN tại vietqr.io/danh-sach-ngan-hang — bắt buộc để tạo được QR.',
                              helperMaxLines: 2,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _accountNumberCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Số tài khoản',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _accountHolderCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tên chủ tài khoản',
                              helperText:
                                  'Không dấu, viết hoa — đúng như trên thẻ ngân hàng.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _minWithdrawalCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'Số dư tối thiểu sau khi tài xế rút ví (đ)',
                              helperText:
                                  'Tài xế không rút được nếu số dư còn lại sau khi rút thấp hơn số này.',
                              helperMaxLines: 2,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [VndInputFormatter()],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(settings.id),
                              child: _saving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Lưu'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PendingOrdersTab extends ConsumerWidget {
  const _PendingOrdersTab();

  Future<void> _confirmPayment(
    BuildContext context,
    WidgetRef ref,
    Order o,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã nhận tiền?'),
        content: Text(
          'Xác nhận đã nhận được ${formatVnd(o.totalAmount)} cho đơn ${o.orderCode}. '
          'Không thể hoàn tác thao tác này — đơn sẽ được xử lý tiếp ngay sau khi xác nhận.',
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

    try {
      await ref.read(adminRepoProvider).confirmPayment(o.id, o.totalAmount);
      ref.invalidate(pendingPaymentOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xác nhận thanh toán đơn ${o.orderCode}')),
        );
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pendingAsync = ref.watch(pendingPaymentOrdersProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đơn đang chờ thanh toán',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Đơn chuyển khoản khách đã đặt nhưng chưa xác nhận có tiền về — bấm '
                '"Xác nhận thanh toán" ngay khi bạn thấy tiền vào tài khoản.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              pendingAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (orders) {
                  if (orders.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Không có đơn nào đang chờ thanh toán.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
                    children: orders
                        .map(
                          (o) => Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () => context.go('/orders/${o.id}'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${o.orderCode} · ${o.merchantName ?? ""}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${o.customerName ?? o.shipRecipientName} — ${formatDateTime(o.createdAt)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          formatVnd(o.totalAmount),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              _confirmPayment(context, ref, o),
                                          child: const Text(
                                            'Xác nhận thanh toán',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              if ((pendingAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                StatCard(
                  label: 'Tổng đơn chờ thanh toán',
                  value: '${pendingAsync.valueOrNull!.length}',
                  icon: Icons.hourglass_empty_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletDepositsTab extends ConsumerWidget {
  const _WalletDepositsTab();

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    DriverWalletRequest r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã nhận tiền?'),
        content: Text(
          'Xác nhận đã nhận được ${formatVnd(r.amount)} nạp ví từ tài xế ${r.driverName}.',
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
    try {
      await ref.read(adminRepoProvider).confirmWalletDeposit(r.id);
      ref.invalidate(pendingWalletDepositsProvider);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cộng tiền vào Ví trên của tài xế')),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final depositsAsync = ref.watch(pendingWalletDepositsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tài xế đang chờ nạp tiền',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Tài xế đã tạo yêu cầu nạp và chuyển khoản vào tài khoản của sàn — bấm "Xác nhận" ngay khi thấy tiền về. Tiền vào thẳng Ví trên (đủ điều kiện nhận đơn mới).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              depositsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Không có yêu cầu nạp tiền nào đang chờ.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
                    children: rows
                        .map(
                          (r) => Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.driverName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${r.driverPhone ?? ""} — ${formatDateTime(r.createdAt)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        formatVnd(r.amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            _confirm(context, ref, r),
                                        child: const Text('Xác nhận'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              if ((depositsAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                StatCard(
                  label: 'Tổng yêu cầu nạp',
                  value: '${depositsAsync.valueOrNull!.length}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletWithdrawalsTab extends ConsumerWidget {
  const _WalletWithdrawalsTab();

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    DriverWalletRequest r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã chuyển khoản?'),
        content: Text(
          'Xác nhận đã chuyển ${formatVnd(r.amount)} cho tài xế ${r.driverName} qua tài khoản ngân hàng ở trên.',
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
    try {
      await ref.read(adminRepoProvider).confirmWalletWithdrawal(r.id);
      ref.invalidate(pendingWalletWithdrawalsProvider);
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xác nhận rút tiền')));
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    DriverWalletRequest r,
  ) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Từ chối yêu cầu rút tiền?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatVnd(r.amount)} sẽ được hoàn lại vào ví tài xế ${r.driverName}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Lý do (không bắt buộc)',
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(adminRepoProvider)
          .rejectWalletWithdrawal(
            r.id,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      ref.invalidate(pendingWalletWithdrawalsProvider);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã từ chối, tiền được hoàn lại ví tài xế'),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final withdrawalsAsync = ref.watch(pendingWalletWithdrawalsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tài xế đang chờ rút tiền',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Tiền đã bị trừ khỏi ví tài xế ngay lúc tạo yêu cầu — quét mã bên dưới để chuyển khoản trả tài xế, '
                'rồi bấm "Xác nhận". Nếu không chuyển được (vd sai thông tin ngân hàng), bấm "Từ chối" để hoàn tiền lại ví.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              withdrawalsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Không có yêu cầu rút tiền nào đang chờ.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
                    children: rows.map((r) {
                      final hasBankInfo =
                          (r.bankBin?.isNotEmpty ?? false) &&
                          (r.bankAccountNumber?.isNotEmpty ?? false);
                      return Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.driverName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '${r.driverPhone ?? ""} — ${formatDateTime(r.createdAt)}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    formatVnd(r.amount),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (!hasBankInfo)
                                Text(
                                  'Tài xế chưa có thông tin ngân hàng.',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              else ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        buildVietQrUrl(
                                          bankBin: r.bankBin!,
                                          accountNumber: r.bankAccountNumber!,
                                          amount: r.amount,
                                          addInfo:
                                              'RUT-${r.id.substring(0, 8).toUpperCase()}',
                                          accountName: r.bankAccountHolder,
                                        ),
                                        width: 160,
                                        height: 160,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const SizedBox(
                                                  width: 160,
                                                  height: 160,
                                                  child: Center(
                                                    child: Text('Lỗi tải QR'),
                                                  ),
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r.bankName ?? ""} · ${r.bankAccountNumber}',
                                          ),
                                          Text(
                                            r.bankAccountHolder ?? '',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.error,
                                      ),
                                      onPressed: () => _reject(context, ref, r),
                                      child: const Text('Từ chối'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () =>
                                          _confirm(context, ref, r),
                                      child: const Text(
                                        'Xác nhận đã chuyển khoản',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              if ((withdrawalsAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                StatCard(
                  label: 'Tổng yêu cầu rút',
                  value: '${withdrawalsAsync.valueOrNull!.length}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MerchantWithdrawalsTab extends ConsumerWidget {
  const _MerchantWithdrawalsTab();

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    MerchantWalletRequest r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã chuyển khoản?'),
        content: Text(
          'Xác nhận đã chuyển ${formatVnd(r.amount)} cho cửa hàng ${r.merchantName} qua tài khoản ngân hàng ở trên.',
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
    try {
      await ref.read(adminRepoProvider).confirmMerchantWalletWithdrawal(r.id);
      ref.invalidate(merchantWalletWithdrawalsProvider);
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xác nhận rút tiền')));
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    MerchantWalletRequest r,
  ) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Từ chối yêu cầu rút tiền?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatVnd(r.amount)} sẽ được hoàn lại vào ví cửa hàng ${r.merchantName}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Lý do (không bắt buộc)',
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(adminRepoProvider)
          .rejectMerchantWalletWithdrawal(
            r.id,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      ref.invalidate(merchantWalletWithdrawalsProvider);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã từ chối, tiền được hoàn lại ví cửa hàng'),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final withdrawalsAsync = ref.watch(merchantWalletWithdrawalsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cửa hàng đang chờ rút tiền',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Tiền đã bị trừ khỏi ví cửa hàng ngay lúc tạo yêu cầu — tự chuyển khoản theo '
                'thông tin ngân hàng bên dưới rồi bấm "Xác nhận". Không chuyển được thì bấm '
                '"Từ chối" để hoàn tiền lại ví.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              withdrawalsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Không có yêu cầu rút tiền nào đang chờ.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
                    children: rows.map((r) {
                      final hasBankInfo =
                          (r.bankName?.isNotEmpty ?? false) &&
                          (r.bankAccountNo?.isNotEmpty ?? false);
                      final hasQr =
                          hasBankInfo && (r.bankBin?.isNotEmpty ?? false);
                      return Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.merchantName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatVnd(r.amount),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (!hasBankInfo)
                                Text(
                                  'Cửa hàng chưa có thông tin ngân hàng.',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              else if (!hasQr) ...[
                                Text(
                                  '${r.bankName} · ${r.bankAccountNo}\n${r.bankAccountName ?? ""}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Chưa chọn lại ngân hàng qua dropdown mới (thiếu mã BIN) nên chưa dựng được QR — cửa hàng vào Sửa hồ sơ chọn lại ngân hàng để có QR lần tới.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        buildVietQrUrl(
                                          bankBin: r.bankBin!,
                                          accountNumber: r.bankAccountNo!,
                                          amount: r.amount,
                                          addInfo:
                                              'RUT-${r.id.substring(0, 8).toUpperCase()}',
                                          accountName: r.bankAccountName,
                                        ),
                                        width: 160,
                                        height: 160,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const SizedBox(
                                                  width: 160,
                                                  height: 160,
                                                  child: Center(
                                                    child: Text('Lỗi tải QR'),
                                                  ),
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r.bankName} · ${r.bankAccountNo}',
                                          ),
                                          Text(
                                            r.bankAccountName ?? '',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.error,
                                      ),
                                      onPressed: () => _reject(context, ref, r),
                                      child: const Text('Từ chối'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () =>
                                          _confirm(context, ref, r),
                                      child: const Text(
                                        'Xác nhận đã chuyển khoản',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              if ((withdrawalsAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                StatCard(
                  label: 'Tổng yêu cầu rút',
                  value: '${withdrawalsAsync.valueOrNull!.length}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BanksTab extends ConsumerWidget {
  const _BanksTab();

  Future<void> _editBank(
    BuildContext context,
    WidgetRef ref, {
    Bank? bank,
  }) async {
    final nameCtrl = TextEditingController(text: bank?.name ?? '');
    final binCtrl = TextEditingController(text: bank?.bin ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bank == null ? 'Thêm ngân hàng' : 'Sửa ngân hàng'),
        content: SizedBox(
          width: dialogWidth(context, 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Tên ngân hàng'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: binCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mã BIN (chuẩn VietQR)',
                  helperText: 'Tra tại vietqr.io/danh-sach-ngan-hang',
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
    if (ok != true ||
        nameCtrl.text.trim().isEmpty ||
        binCtrl.text.trim().isEmpty)
      return;

    try {
      if (bank == null) {
        await ref
            .read(adminRepoProvider)
            .createBank(name: nameCtrl.text.trim(), bin: binCtrl.text.trim());
      } else {
        await ref.read(adminRepoProvider).updateBank(bank.id, {
          'name': nameCtrl.text.trim(),
          'bin': binCtrl.text.trim(),
        });
      }
      ref.invalidate(banksProvider);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _deleteBank(
    BuildContext context,
    WidgetRef ref,
    Bank bank,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá ngân hàng?'),
        content: Text(
          'Xoá "${bank.name}" khỏi danh sách — tài xế đã chọn ngân hàng này trước đó không bị ảnh hưởng.',
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
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepoProvider).deleteBank(bank.id);
      ref.invalidate(banksProvider);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final banksAsync = ref.watch(banksProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editBank(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Danh sách ngân hàng', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Tài xế chọn từ danh sách này (dropdown) lúc đăng ký/sửa hồ sơ, thay vì tự gõ tên/mã ngân hàng.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                banksAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (banks) {
                    if (banks.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Chưa có ngân hàng nào — bấm nút + để thêm.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }
                    return Column(
                      children: banks
                          .map(
                            (b) => Card(
                              elevation: 0,
                              color: theme.colorScheme.surfaceContainerLow,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  b.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text('Mã BIN: ${b.bin}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _editBank(context, ref, bank: b),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _deleteBank(context, ref, b),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                if ((banksAsync.valueOrNull?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 16),
                  StatCard(
                    label: 'Tổng ngân hàng',
                    value: '${banksAsync.valueOrNull!.length}',
                    icon: Icons.account_balance_outlined,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
