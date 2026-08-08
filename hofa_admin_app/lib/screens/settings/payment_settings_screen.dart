import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/bank_account_settings.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';

/// 2 nội dung: (1) thông tin tài khoản ngân hàng dùng tạo mã VietQR cho khách quét chuyển
/// khoản (app khách tự dựng URL ảnh QR từ thông tin này, xem core/vietqr.dart phía app khách),
/// (2) danh sách đơn đang chờ thanh toán (pending_payment) kèm nút xác nhận tay khi tiền đã về.
class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  ConsumerState<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> {
  final _bankNameCtrl = TextEditingController();
  final _bankBinCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankBinCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(BankAccountSettings s) {
    _bankNameCtrl.text = s.bankName ?? '';
    _bankBinCtrl.text = s.bankBin ?? '';
    _accountNumberCtrl.text = s.accountNumber ?? '';
    _accountHolderCtrl.text = s.accountHolderName ?? '';
  }

  Future<void> _save(String? id) async {
    setState(() => _saving = true);
    try {
      final saved = await ref.read(adminRepoProvider).updateBankAccountSettings(
            BankAccountSettings(
              id: id,
              bankName: _bankNameCtrl.text.trim(),
              bankBin: _bankBinCtrl.text.trim(),
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolderName: _accountHolderCtrl.text.trim(),
            ),
          );
      ref.invalidate(bankAccountSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu thông tin ngân hàng')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmPayment(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã nhận tiền?'),
        content: Text('Xác nhận đã nhận được ${formatVnd(o.totalAmount)} cho đơn ${o.orderCode}. '
            'Không thể hoàn tác thao tác này — đơn sẽ được xử lý tiếp ngay sau khi xác nhận.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(adminRepoProvider).confirmPayment(o.id, o.totalAmount);
      ref.invalidate(pendingPaymentOrdersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xác nhận thanh toán đơn ${o.orderCode}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(bankAccountSettingsProvider);
    final pendingAsync = ref.watch(pendingPaymentOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thanh toán')),
      body: settingsAsync.when(
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
                      'phương thức "Chuyển khoản ngân hàng". Miễn phí, không cần tài khoản/API '
                      'của cổng thanh toán nào.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
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
                                helperText: 'Tra mã BIN tại vietqr.io/danh-sach-ngan-hang — bắt buộc để tạo được QR.',
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
                                helperText: 'Không dấu, viết hoa — đúng như trên thẻ ngân hàng.',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _saving ? null : () => _save(settings.id),
                                child: _saving
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Lưu'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text('Đơn đang chờ thanh toán', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Đơn chuyển khoản khách đã đặt nhưng chưa xác nhận có tiền về — bấm '
                      '"Xác nhận thanh toán" ngay khi bạn thấy tiền vào tài khoản.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    pendingAsync.when(
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                      error: (e, _) => Text('Lỗi: $e'),
                      data: (orders) {
                        if (orders.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('Không có đơn nào đang chờ thanh toán.', style: theme.textTheme.bodyMedium),
                          );
                        }
                        return Column(
                          children: orders
                              .map(
                                (o) => Card(
                                  elevation: 0,
                                  color: theme.colorScheme.surfaceContainerLow,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    onTap: () => context.go('/orders/${o.id}'),
                                    title: Text('${o.orderCode} · ${o.merchantName ?? ""}',
                                        style: const TextStyle(fontWeight: FontWeight.w500)),
                                    subtitle: Text(
                                      '${o.customerName ?? o.shipRecipientName} — ${formatDateTime(o.createdAt)}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(formatVnd(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 12),
                                        FilledButton(
                                          onPressed: () => _confirmPayment(o),
                                          child: const Text('Xác nhận thanh toán'),
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
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
