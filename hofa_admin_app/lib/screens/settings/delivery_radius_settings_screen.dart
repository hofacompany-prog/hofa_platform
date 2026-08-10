import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/delivery_radius_settings.dart';
import '../../providers/admin_providers.dart';

/// Bán kính giao hàng mặc định toàn sàn — trần nới rộng thêm cho chi nhánh có bán kính riêng
/// (đặt lúc thêm/sửa chi nhánh, app cửa hàng) nhỏ hơn mức này. Khách ngoài CẢ 2 mức (riêng chi
/// nhánh lẫn mặc định này) sẽ không thấy cửa hàng/sản phẩm đó; ngoài riêng bán kính chi nhánh
/// nhưng vẫn trong mức mặc định thì vẫn thấy, khoảng cách hiện màu cam cảnh báo.
class DeliveryRadiusSettingsScreen extends ConsumerStatefulWidget {
  const DeliveryRadiusSettingsScreen({super.key});

  @override
  ConsumerState<DeliveryRadiusSettingsScreen> createState() =>
      _DeliveryRadiusSettingsScreenState();
}

class _DeliveryRadiusSettingsScreenState
    extends ConsumerState<DeliveryRadiusSettingsScreen> {
  final _radiusCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(DeliveryRadiusSettings s) {
    _radiusCtrl.text = _trimZero(s.defaultRadiusKm);
  }

  String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _save(String? id) async {
    final radius = double.tryParse(_radiusCtrl.text.trim());
    if (radius == null || radius <= 0 || radius > 100) {
      _showError('Bán kính phải lớn hơn 0 và tối đa 100km');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateDeliveryRadiusSettings(
            DeliveryRadiusSettings(id: id, defaultRadiusKm: radius),
          );
      ref.invalidate(deliveryRadiusSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu bán kính giao hàng mặc định')),
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
    final settingsAsync = ref.watch(deliveryRadiusSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bán kính giao hàng')),
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
                      'Mỗi chi nhánh tự đặt bán kính giao hàng riêng lúc thêm/sửa chi nhánh '
                      '(app cửa hàng). Mức mặc định ở đây đóng vai trò trần nới rộng thêm cho '
                      'chi nhánh đặt bán kính riêng nhỏ hơn mức này.',
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
                            TextField(
                              controller: _radiusCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Bán kính giao hàng mặc định',
                                suffixText: 'km',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Khách ngoài CẢ bán kính riêng của chi nhánh LẪN mức mặc định này '
                              'sẽ không thấy cửa hàng/sản phẩm. Ngoài riêng bán kính chi nhánh '
                              'nhưng vẫn trong mức mặc định thì vẫn thấy, khoảng cách hiện màu '
                              'cam cảnh báo cho khách.',
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
