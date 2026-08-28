import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_update_setting.dart';
import '../../providers/admin_providers.dart';

/// Ép cập nhật app native (Khách hàng/Tài xế/Cửa hàng) — không áp dụng app Admin (web-only,
/// không phát hành qua store, đã có PwaVersionService riêng). Máy khách so build number CÀI
/// THẬT với minBuildNumber ở đây, thấp hơn thì hiện popup KHÔNG có nút bỏ qua, chỉ mở được store
/// đúng nền tảng — xem hofa-db/100_app_update_settings.sql,
/// hofa_customer_app/lib/core/app_update_service.dart (và tương tự ở app tài xế/cửa hàng).
class AppUpdateSettingsScreen extends ConsumerWidget {
  const AppUpdateSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(appUpdateSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Số build tối thiểu (build number trong pubspec.yaml, phần sau dấu +) — máy '
                'khách đang cài thấp hơn số này sẽ bị chặn dùng app, chỉ hiện popup mở store để '
                'cập nhật, không có nút bỏ qua. Để trống link store thì nút "Cập nhật ngay" sẽ '
                'không bấm được — nhớ điền trước khi tăng số build tối thiểu.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              settingsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (list) => Column(
                  children: [
                    for (final scope in const ['customer', 'driver', 'merchant']) ...[
                      _AppUpdateSection(
                        appScope: scope,
                        setting: _findByScope(list, scope),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

AppUpdateSetting? _findByScope(List<AppUpdateSetting> list, String scope) {
  for (final s in list) {
    if (s.appScope == scope) return s;
  }
  return null;
}

class _AppUpdateSection extends ConsumerStatefulWidget {
  final String appScope;
  final AppUpdateSetting? setting;
  const _AppUpdateSection({required this.appScope, required this.setting});

  @override
  ConsumerState<_AppUpdateSection> createState() => _AppUpdateSectionState();
}

class _AppUpdateSectionState extends ConsumerState<_AppUpdateSection> {
  final _buildCtrl = TextEditingController();
  final _iosCtrl = TextEditingController();
  final _androidCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _buildCtrl.dispose();
    _iosCtrl.dispose();
    _androidCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(AppUpdateSetting? s) {
    _buildCtrl.text = '${s?.minBuildNumber ?? 1}';
    _iosCtrl.text = s?.iosStoreUrl ?? '';
    _androidCtrl.text = s?.androidStoreUrl ?? '';
  }

  Future<void> _save() async {
    final minBuild = int.tryParse(_buildCtrl.text.trim());
    if (minBuild == null || minBuild <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số build tối thiểu không hợp lệ')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepoProvider)
          .updateAppUpdateSettings(
            AppUpdateSetting(
              appScope: widget.appScope,
              minBuildNumber: minBuild,
              iosStoreUrl: _iosCtrl.text.trim().isEmpty ? null : _iosCtrl.text.trim(),
              androidStoreUrl: _androidCtrl.text.trim().isEmpty ? null : _androidCtrl.text.trim(),
            ),
          );
      ref.invalidate(appUpdateSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu')));
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
    if (!_initialized) {
      _fillFrom(widget.setting);
      _initialized = true;
    }
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appScopeLabels[widget.appScope] ?? widget.appScope,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buildCtrl,
              decoration: const InputDecoration(
                labelText: 'Số build tối thiểu',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _iosCtrl,
              decoration: const InputDecoration(
                labelText: 'Link App Store (iOS)',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'https://apps.apple.com/app/id...',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _androidCtrl,
              decoration: const InputDecoration(
                labelText: 'Link CH Play (Android)',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'https://play.google.com/store/apps/details?id=...',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lưu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
