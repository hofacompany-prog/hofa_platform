import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pwa_reminder_settings.dart';
import '../../providers/admin_providers.dart';

/// Chu kỳ nhắc cài PWA cho app Khách — khách chưa cài sẽ thấy popup nhắc lại đúng mỗi N phút
/// khi đang lướt app (xem hofa_customer_app CustomerShell), dừng hẳn khi đã cài xong. Không còn
/// chặn cứng luồng đặt hàng như trước (đã bỏ requirePwaInstall).
class PwaReminderSettingsScreen extends ConsumerStatefulWidget {
  const PwaReminderSettingsScreen({super.key});

  @override
  ConsumerState<PwaReminderSettingsScreen> createState() =>
      _PwaReminderSettingsScreenState();
}

class _PwaReminderSettingsScreenState
    extends ConsumerState<PwaReminderSettingsScreen> {
  final _minutesCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _minutesCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(PwaReminderSettings s) {
    _minutesCtrl.text = '${s.intervalMinutes}';
  }

  Future<void> _save(String? id) async {
    final minutes = int.tryParse(_minutesCtrl.text.trim());
    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập số phút hợp lệ (lớn hơn 0)')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updatePwaReminderSettings(
            PwaReminderSettings(id: id, intervalMinutes: minutes),
          );
      ref.invalidate(pwaReminderSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu chu kỳ nhắc')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(pwaReminderSettingsProvider);

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
                    'Chu kỳ nhắc cài PWA (app Khách)',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Khách chưa cài app lên máy sẽ thấy popup nhắc cài lại đúng mỗi N phút, '
                    'bất kể đang ở trang nào của app — không còn chặn đặt hàng như trước. Khách '
                    'đã cài rồi sẽ không thấy popup này nữa.',
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
                            controller: _minutesCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Số phút',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
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
