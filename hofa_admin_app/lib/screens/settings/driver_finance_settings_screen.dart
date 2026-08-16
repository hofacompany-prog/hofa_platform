import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/driver_finance_settings.dart';
import '../../providers/admin_providers.dart';

/// % HOFA cắt trên phí giao (driver_fee) toàn sàn — xem hofa-db/69_driver_wallet_vi_tren.sql.
/// driver_fee_commission_rate mặc định 0 (an toàn, không tự động giảm thu nhập tài xế cho tới
/// khi admin chủ động đặt tỷ lệ khác 0). Không còn cấu hình "hạn mức COD" — Ví trên giờ là vốn,
/// không phải nợ COD cần giới hạn (cod_debt_limit vẫn còn trong DB nhưng không đụng tới nữa).
class DriverFinanceSettingsScreen extends ConsumerStatefulWidget {
  const DriverFinanceSettingsScreen({super.key});

  @override
  ConsumerState<DriverFinanceSettingsScreen> createState() =>
      _DriverFinanceSettingsScreenState();
}

class _DriverFinanceSettingsScreenState
    extends ConsumerState<DriverFinanceSettingsScreen> {
  final _rateCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _pitCtrl = TextEditingController();
  final _feeShareCtrl = TextEditingController();
  final _minWithdrawalCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _rateCtrl.dispose();
    _vatCtrl.dispose();
    _pitCtrl.dispose();
    _feeShareCtrl.dispose();
    _minWithdrawalCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(DriverFinanceSettings s) {
    _rateCtrl.text = _trimZero(s.driverFeeCommissionRate);
    _vatCtrl.text = _trimZero(s.vatRate);
    _pitCtrl.text = _trimZero(s.pitRate);
    _feeShareCtrl.text = _trimZero(s.buyOnBehalfFeeShareRate);
    _minWithdrawalCtrl.text = VndInputFormatter.display(s.minWithdrawalAmount);
  }

  String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _save(DriverFinanceSettings current) async {
    final rate = double.tryParse(_rateCtrl.text.trim());
    final vat = double.tryParse(_vatCtrl.text.trim());
    final pit = double.tryParse(_pitCtrl.text.trim());
    final feeShare = double.tryParse(_feeShareCtrl.text.trim());
    final minWithdrawal = VndInputFormatter.parse(_minWithdrawalCtrl.text);
    if (rate == null ||
        rate < 0 ||
        rate > 100 ||
        vat == null ||
        vat < 0 ||
        vat > 100 ||
        pit == null ||
        pit < 0 ||
        pit > 100 ||
        feeShare == null ||
        feeShare < 0 ||
        feeShare > 100) {
      _showError('Các tỷ lệ % phải từ 0 đến 100');
      return;
    }
    if (minWithdrawal == null || minWithdrawal < 0) {
      _showError('Số tiền rút tối thiểu phải là số nguyên từ 0 trở lên');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateDriverFinanceSettings(
            DriverFinanceSettings(
              id: current.id,
              driverFeeCommissionRate: rate,
              vatRate: vat,
              pitRate: pit,
              codDebtLimit: current.codDebtLimit,
              buyOnBehalfFeeShareRate: feeShare,
              minWithdrawalAmount: minWithdrawal,
            ),
          );
      ref.invalidate(driverFinanceSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cấu hình tài chính tài xế')),
        );
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(driverFinanceSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài chính tài xế')),
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
                      'Áp dụng cho toàn sàn — ảnh hưởng tới mọi chuyến giao mới tính từ lúc lưu, '
                      'không tính lại các chuyến đã giao trước đó.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '% HOFA cắt trên phí giao',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                suffixText: '%',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mặc định 0% — tài xế nhận nguyên phí giao. Đặt khác 0 thì tài xế '
                              'chỉ nhận phần còn lại sau khi trừ % này.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
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
                            Text(
                              'Thuế suất trên phí giao',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _vatCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Thuế GTGT',
                                      suffixText: '%',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _pitCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Thuế TNCN',
                                      suffixText: '%',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mặc định 0% — cùng cách tính với cửa hàng (trừ thẳng lên phí '
                              'giao, không lồng thuế trong thuế). Tài xế thấy rõ khoản trừ này ở '
                              'chi tiết chuyến giao và màn Thu nhập.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
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
                            Text(
                              'Chia sẻ phí mua hộ cho tài xế',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _feeShareCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                suffixText: '%',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Áp dụng CHUNG cho mọi tài xế — % của phí mua hộ (đã tính theo '
                              'bậc riêng từng cửa hàng ở màn Chi tiết cửa hàng) tài xế được '
                              'nhận thêm khi giao đơn mua hộ. Mặc định 0% — không cộng thêm '
                              'gì. Cộng thẳng vào ví thu nhập, không trừ hoa hồng/thuế ở trên.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
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
                            Text(
                              'Số tiền rút tối thiểu / lần',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _minWithdrawalCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [VndInputFormatter()],
                              decoration: const InputDecoration(
                                suffixText: 'đ',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mặc định 0đ — không giới hạn. Đặt khác 0 để chặn tài xế gửi yêu '
                              'cầu rút số tiền vặt (vd 1-2đ), làm phình danh sách chờ duyệt.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(settings),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lưu cấu hình'),
                      ),
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
