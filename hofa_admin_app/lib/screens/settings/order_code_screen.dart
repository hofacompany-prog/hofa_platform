import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/order_settings.dart';
import '../../providers/admin_providers.dart';

/// Chỉnh chữ đầu (prefix) của mã đơn hàng hiển thị, vd 'HF' -> mã đơn dạng 'HF-482'.
/// 3 chữ số sau dấu gạch ngang là ngẫu nhiên, sinh tự động trong database lúc tạo đơn
/// (xem generate_order_code() trong hofa-db/01_schema.sql) — không chỉnh được ở đây.
class OrderCodeScreen extends ConsumerStatefulWidget {
  const OrderCodeScreen({super.key});

  @override
  ConsumerState<OrderCodeScreen> createState() => _OrderCodeScreenState();
}

class _OrderCodeScreenState extends ConsumerState<OrderCodeScreen> {
  final _prefixCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _prefixCtrl.dispose();
    super.dispose();
  }

  String get _prefixDraft {
    final v = _prefixCtrl.text.trim().toUpperCase();
    return v.isEmpty ? 'HF' : v;
  }

  Future<void> _save(String? id) async {
    final prefix = _prefixCtrl.text.trim().toUpperCase();
    if (prefix.isEmpty || !RegExp(r'^[A-Z0-9]{1,10}$').hasMatch(prefix)) {
      _showError(
        'Chữ đầu chỉ gồm chữ/số, tối đa 10 ký tự, không được để trống',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateOrderSettings(OrderSettings(id: id, codePrefix: prefix));
      ref.invalidate(orderSettingsProvider);
      if (mounted) {
        _prefixCtrl.text = saved.codePrefix;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu chữ đầu mã đơn hàng')),
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
    final settingsAsync = ref.watch(orderSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mã đơn hàng')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) {
          if (!_initialized) {
            _prefixCtrl.text = settings.codePrefix;
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
                      'Mỗi đơn hàng được đặt tên tự động dạng "Chữ đầu-3 số ngẫu nhiên" '
                      '(vd HF-482) để đọc nhanh qua điện thoại. Áp dụng cho toàn sàn, chỉ '
                      'chỉnh được chữ đầu, 3 số sau luôn ngẫu nhiên và có thể trùng giữa '
                      'các đơn khác nhau — hệ thống vẫn xử lý đơn bằng mã nội bộ thật, '
                      'không dựa vào mã này.',
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
                              'Chữ đầu mã đơn hàng',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _prefixCtrl,
                              maxLength: 10,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp('[A-Za-z0-9]'),
                                ),
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Chữ đầu (vd HF)',
                                helperText:
                                    'Chỉ gồm chữ và số, tối đa 10 ký tự',
                                border: OutlineInputBorder(),
                              ),
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
                              'Xem trước',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '$_prefixDraft-482, $_prefixDraft-051, $_prefixDraft-930 ...',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
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
                            : const Text('Lưu'),
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
