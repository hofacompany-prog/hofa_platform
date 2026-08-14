import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/admin_contact_settings.dart';
import '../../providers/admin_providers.dart';

/// SĐT liên hệ admin/hỗ trợ toàn sàn — app khách gọi/nhắn tin thẳng số này ở nút "Liên hệ hỗ
/// trợ" trên màn chi tiết cửa hàng MUA HỘ (cửa hàng mua hộ không trực tiếp xử lý đơn, khách
/// cần liên hệ admin thay vì cửa hàng khi có vấn đề).
class AdminContactSettingsScreen extends ConsumerStatefulWidget {
  const AdminContactSettingsScreen({super.key});

  @override
  ConsumerState<AdminContactSettingsScreen> createState() =>
      _AdminContactSettingsScreenState();
}

class _AdminContactSettingsScreenState
    extends ConsumerState<AdminContactSettingsScreen> {
  final _phoneCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(AdminContactSettings s) {
    _phoneCtrl.text = s.phone ?? '';
  }

  Future<void> _save(String? id) async {
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateAdminContactSettings(
            AdminContactSettings(id: id, phone: _phoneCtrl.text.trim()),
          );
      ref.invalidate(adminContactSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu SĐT liên hệ')));
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
    final settingsAsync = ref.watch(adminContactSettingsProvider);

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
                    'SĐT liên hệ admin/hỗ trợ',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hiện ở nút "Liên hệ hỗ trợ" trên màn chi tiết cửa hàng MUA HỘ trong app '
                    'khách — cửa hàng mua hộ không trực tiếp xử lý đơn (tài xế tự đi mua), nên '
                    'khách bấm vào nút đó sẽ gọi/nhắn tin thẳng cho số này thay vì cho cửa hàng.',
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
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Số điện thoại',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
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
