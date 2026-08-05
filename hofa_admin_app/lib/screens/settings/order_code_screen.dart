import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/order_settings.dart';
import '../../providers/admin_providers.dart';

/// Chỉnh chữ đầu (prefix) của mã đơn hàng hiển thị — 2 loại theo sales_model:
/// giao ngay (instant) và đặt trước/giá sỉ (scheduled), vd 'HF' -> 'HF-482'.
/// 3 chữ số sau dấu gạch ngang là ngẫu nhiên, sinh tự động trong database lúc tạo đơn
/// (xem generate_order_code() trong hofa-db/01_schema.sql) — không chỉnh được ở đây.
class OrderCodeScreen extends ConsumerStatefulWidget {
  const OrderCodeScreen({super.key});

  @override
  ConsumerState<OrderCodeScreen> createState() => _OrderCodeScreenState();
}

class _OrderCodeScreenState extends ConsumerState<OrderCodeScreen> {
  final _instantCtrl = TextEditingController();
  final _scheduledCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _instantCtrl.dispose();
    _scheduledCtrl.dispose();
    super.dispose();
  }

  String _draft(TextEditingController ctrl, String fallback) {
    final v = ctrl.text.trim().toUpperCase();
    return v.isEmpty ? fallback : v;
  }

  String? _validate(String raw, String label) {
    final v = raw.trim().toUpperCase();
    if (v.isEmpty || !RegExp(r'^[A-Z0-9]{1,10}$').hasMatch(v)) {
      return 'Chữ đầu $label chỉ gồm chữ/số, tối đa 10 ký tự, không được để trống';
    }
    return null;
  }

  Future<void> _save(String? id) async {
    final instant = _instantCtrl.text.trim().toUpperCase();
    final scheduled = _scheduledCtrl.text.trim().toUpperCase();
    final instantError = _validate(instant, 'đơn giao ngay');
    if (instantError != null) {
      _showError(instantError);
      return;
    }
    final scheduledError = _validate(scheduled, 'đơn đặt trước/giá sỉ');
    if (scheduledError != null) {
      _showError(scheduledError);
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateOrderSettings(
            OrderSettings(
              id: id,
              codePrefixInstant: instant,
              codePrefixScheduled: scheduled,
            ),
          );
      ref.invalidate(orderSettingsProvider);
      if (mounted) {
        _instantCtrl.text = saved.codePrefixInstant;
        _scheduledCtrl.text = saved.codePrefixScheduled;
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
            _instantCtrl.text = settings.codePrefixInstant;
            _scheduledCtrl.text = settings.codePrefixScheduled;
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
                      '(vd HF-482) để đọc nhanh qua điện thoại. Đơn giao ngay và đơn đặt '
                      'trước/giá sỉ dùng chữ đầu khác nhau để phân biệt nhanh. Áp dụng cho '
                      'toàn sàn, chỉ chỉnh được chữ đầu — 3 số sau luôn ngẫu nhiên và có '
                      'thể trùng giữa các đơn khác nhau, hệ thống vẫn xử lý đơn bằng mã '
                      'nội bộ thật, không dựa vào mã này.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PrefixCard(
                      title: 'Đơn giao ngay',
                      subtitle: 'Áp dụng cho đơn hàng có sẵn, giao ngay',
                      controller: _instantCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _PrefixCard(
                      title: 'Đơn đặt trước / giá sỉ',
                      subtitle:
                          'Áp dụng cho đơn đặt trước hoặc mua sỉ, giao theo lịch',
                      controller: _scheduledCtrl,
                      onChanged: () => setState(() {}),
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
                            _PreviewRow(
                              label: 'Giao ngay',
                              prefix: _draft(_instantCtrl, 'HF'),
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 6),
                            _PreviewRow(
                              label: 'Đặt trước / giá sỉ',
                              prefix: _draft(_scheduledCtrl, 'DT'),
                              color: theme.colorScheme.secondary,
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

class _PrefixCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _PrefixCard({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.onChanged,
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
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 10,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              ],
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Chữ đầu',
                helperText: 'Chỉ gồm chữ và số, tối đa 10 ký tự',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String prefix;
  final Color color;

  const _PreviewRow({
    required this.label,
    required this.prefix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            '$prefix-482, $prefix-051, $prefix-930 ...',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
