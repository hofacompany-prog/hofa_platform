import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/small_order_fee_settings.dart';
import '../../providers/admin_providers.dart';

/// Cấu hình phí đơn nhỏ/lẻ — áp dụng cho TOÀN SÀN (mọi loại cửa hàng, kể cả mua hộ). Đơn có
/// giá trị (subtotal) dưới ngưỡng cấu hình thì cộng thêm 1 khoản phí cố định vào tổng tiền —
/// xem hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql.
class SmallOrderFeeScreen extends ConsumerStatefulWidget {
  const SmallOrderFeeScreen({super.key});

  @override
  ConsumerState<SmallOrderFeeScreen> createState() =>
      _SmallOrderFeeScreenState();
}

class _SmallOrderFeeScreenState extends ConsumerState<SmallOrderFeeScreen> {
  final _thresholdCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  bool _isActive = true;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(SmallOrderFeeSettings s) {
    _isActive = s.isActive;
    _thresholdCtrl.text = VndInputFormatter.display(s.thresholdAmount);
    _feeCtrl.text = VndInputFormatter.display(s.feeAmount);
  }

  Future<void> _save(String? id) async {
    final threshold = VndInputFormatter.parse(_thresholdCtrl.text);
    final fee = VndInputFormatter.parse(_feeCtrl.text);
    if (threshold == null || threshold < 0) {
      _showError('Ngưỡng giá trị đơn không hợp lệ');
      return;
    }
    if (fee == null || fee < 0) {
      _showError('Phí cộng thêm không hợp lệ');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateSmallOrderFeeSettings(
            SmallOrderFeeSettings(
              id: id,
              isActive: _isActive,
              thresholdAmount: threshold,
              feeAmount: fee,
            ),
          );
      ref.invalidate(smallOrderFeeSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cấu hình phí đơn nhỏ')),
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
    final settingsAsync = ref.watch(smallOrderFeeSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Phí đơn nhỏ')),
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
                      'Áp dụng cho TOÀN SÀN — mọi loại cửa hàng (kể cả mua hộ). Đơn có giá trị '
                      'dưới ngưỡng bên dưới sẽ tự cộng thêm phí vào tổng tiền khách trả.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Bật tính phí đơn nhỏ',
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tính phí cho đơn giá trị nhỏ'),
                        subtitle: const Text(
                          'Tắt thì mọi đơn đều không bị cộng phí này, dù dưới ngưỡng',
                        ),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Ngưỡng và mức phí',
                      enabled: _isActive,
                      child: Column(
                        children: [
                          TextField(
                            controller: _thresholdCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            inputFormatters: [VndInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Mức tính phí — đơn dưới (VNĐ)',
                              helperText:
                                  'Đơn có giá trị (subtotal) dưới số này mới bị tính phí',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _feeCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            inputFormatters: [VndInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Phí cộng thêm (VNĐ)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(settings.id),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool enabled;
  const _SectionCard({
    required this.title,
    required this.child,
    this.enabled = true,
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
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: enabled ? null : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Opacity(opacity: enabled ? 1 : 0.5, child: child),
          ],
        ),
      ),
    );
  }
}
