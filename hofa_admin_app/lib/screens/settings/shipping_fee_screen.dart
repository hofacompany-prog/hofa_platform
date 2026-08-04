import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/shipping_fee_settings.dart';
import '../../providers/admin_providers.dart';

/// Cấu hình phí ship áp dụng cho toàn sàn (1 công thức chung, không theo từng cửa hàng).
/// Công thức: phí cơ bản cho X km đầu + phí/km cho phần vượt, có thể giới hạn phí tối đa
/// và miễn phí khi đơn đạt giá trị tối thiểu — cùng kiểu công thức đang dùng để tính phí
/// trả tài xế, cho nhất quán trong toàn hệ thống.
class ShippingFeeScreen extends ConsumerStatefulWidget {
  const ShippingFeeScreen({super.key});

  @override
  ConsumerState<ShippingFeeScreen> createState() => _ShippingFeeScreenState();
}

class _ShippingFeeScreenState extends ConsumerState<ShippingFeeScreen> {
  final _baseFeeCtrl = TextEditingController();
  final _baseDistanceCtrl = TextEditingController();
  final _perKmFeeCtrl = TextEditingController();
  final _freeShipThresholdCtrl = TextEditingController();
  final _maxFeeCtrl = TextEditingController();
  final _roundToCtrl = TextEditingController();
  bool _isActive = true;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _baseFeeCtrl.dispose();
    _baseDistanceCtrl.dispose();
    _perKmFeeCtrl.dispose();
    _freeShipThresholdCtrl.dispose();
    _maxFeeCtrl.dispose();
    _roundToCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(ShippingFeeSettings s) {
    _isActive = s.isActive;
    _baseFeeCtrl.text = s.baseFee.toString();
    _baseDistanceCtrl.text = _trimZero(s.baseDistanceKm);
    _perKmFeeCtrl.text = s.perKmFee.toString();
    _freeShipThresholdCtrl.text = s.freeShipThreshold?.toString() ?? '';
    _maxFeeCtrl.text = s.maxFee?.toString() ?? '';
    _roundToCtrl.text = s.roundTo.toString();
  }

  String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  ShippingFeeSettings _currentDraft(String? id) => ShippingFeeSettings(
    id: id,
    isActive: _isActive,
    baseFee: int.tryParse(_baseFeeCtrl.text.trim()) ?? 0,
    baseDistanceKm: double.tryParse(_baseDistanceCtrl.text.trim()) ?? 0,
    perKmFee: int.tryParse(_perKmFeeCtrl.text.trim()) ?? 0,
    freeShipThreshold: int.tryParse(_freeShipThresholdCtrl.text.trim()),
    maxFee: int.tryParse(_maxFeeCtrl.text.trim()),
    roundTo: int.tryParse(_roundToCtrl.text.trim()) ?? 500,
  );

  Future<void> _save(String? id) async {
    final baseFee = int.tryParse(_baseFeeCtrl.text.trim());
    final baseDistance = double.tryParse(_baseDistanceCtrl.text.trim());
    final perKmFee = int.tryParse(_perKmFeeCtrl.text.trim());
    final roundTo = int.tryParse(_roundToCtrl.text.trim());
    if (baseFee == null || baseFee < 0) {
      _showError('Phí cơ bản không hợp lệ');
      return;
    }
    if (baseDistance == null || baseDistance < 0) {
      _showError('Số km đầu không hợp lệ');
      return;
    }
    if (perKmFee == null || perKmFee < 0) {
      _showError('Phí mỗi km không hợp lệ');
      return;
    }
    if (roundTo == null || roundTo <= 0) {
      _showError('Làm tròn phí không hợp lệ');
      return;
    }
    final maxFeeText = _maxFeeCtrl.text.trim();
    final maxFee = maxFeeText.isEmpty ? null : int.tryParse(maxFeeText);
    if (maxFeeText.isNotEmpty && maxFee == null) {
      _showError('Phí ship tối đa không hợp lệ');
      return;
    }
    final thresholdText = _freeShipThresholdCtrl.text.trim();
    final threshold = thresholdText.isEmpty
        ? null
        : int.tryParse(thresholdText);
    if (thresholdText.isNotEmpty && threshold == null) {
      _showError('Giá trị đơn miễn phí ship không hợp lệ');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateShippingFeeSettings(
            ShippingFeeSettings(
              id: id,
              isActive: _isActive,
              baseFee: baseFee,
              baseDistanceKm: baseDistance,
              perKmFee: perKmFee,
              freeShipThreshold: threshold,
              maxFee: maxFee,
              roundTo: roundTo,
            ),
          );
      ref.invalidate(shippingFeeSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cấu hình phí ship')),
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
    final settingsAsync = ref.watch(shippingFeeSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Phí ship')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) {
          if (!_initialized) {
            _fillFrom(settings);
            _initialized = true;
          }
          final draft = _currentDraft(settings.id);

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Áp dụng cho toàn sàn — 1 công thức chung tính theo khoảng cách '
                      'từ chi nhánh đến địa chỉ giao, không cài riêng theo từng cửa hàng.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Bật tính phí ship',
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tính phí ship cho đơn hàng'),
                        subtitle: const Text(
                          'Tắt thì mọi đơn đều miễn phí ship, các mục bên dưới bị bỏ qua',
                        ),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Công thức theo khoảng cách',
                      enabled: _isActive,
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _baseFeeCtrl,
                                  enabled: _isActive,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Phí cơ bản (VNĐ)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _baseDistanceCtrl,
                                  enabled: _isActive,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Cho bao nhiêu km đầu',
                                    suffixText: 'km',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _perKmFeeCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Phí mỗi km tiếp theo (VNĐ/km)',
                              helperText:
                                  'Áp dụng cho phần quãng đường vượt số km đầu ở trên',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Ưu đãi & giới hạn (tuỳ chọn)',
                      enabled: _isActive,
                      child: Column(
                        children: [
                          TextField(
                            controller: _freeShipThresholdCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Miễn phí ship khi đơn từ (VNĐ)',
                              helperText:
                                  'Để trống = không áp dụng miễn phí theo giá trị đơn',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _maxFeeCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Phí ship tối đa (VNĐ)',
                              helperText: 'Để trống = không giới hạn',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _roundToCtrl,
                            enabled: _isActive,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText:
                                  'Làm tròn phí ship đến bội số của (VNĐ)',
                              helperText:
                                  'VD: 500 nghĩa là phí luôn là bội số của 500đ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Xem trước',
                      child: _isActive
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phí ship ước tính theo vài khoảng cách mẫu, với đơn hàng '
                                  'chưa đạt mức miễn phí:',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                ...const [1.0, 3.0, 5.0, 10.0, 15.0].map(
                                  (km) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Khoảng cách ${_trimZero(km)} km'),
                                        Text(
                                          formatVnd(draft.estimate(km)),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Đang tắt tính phí ship — mọi đơn hàng sẽ miễn phí ship.',
                              style: theme.textTheme.bodyMedium,
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
