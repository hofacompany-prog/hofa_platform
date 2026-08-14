import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_accept_settings.dart';
import '../../models/driver_dispatch_settings.dart';
import '../../providers/admin_providers.dart';

/// Tham số toàn sàn cho thanh trượt "Nhận đơn" ở màn nhận đơn của tài xế (driver app) —
/// riêng biệt với "Thông số cửa hàng" (auto_accept_settings), không cài theo từng tài xế.
/// Màn nhận đơn LUÔN hiện khi có đơn mới (không còn nhánh bỏ qua thẳng như trước) — chỉ khác
/// thời lượng + hậu quả hết giờ theo công tắc "Tự động nhận đơn" tài xế tự bật ở Trang chủ
/// (drivers.auto_accept): bật thì hết giờ tự nhận, tắt thì hết giờ tự chuyển tài xế khác.
class DriverAcceptSettingsScreen extends ConsumerStatefulWidget {
  const DriverAcceptSettingsScreen({super.key});

  @override
  ConsumerState<DriverAcceptSettingsScreen> createState() =>
      _DriverAcceptSettingsScreenState();
}

class _DriverAcceptSettingsScreenState
    extends ConsumerState<DriverAcceptSettingsScreen> {
  final _autoCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  final _rescanIntervalCtrl = TextEditingController();
  final _maxRescanAttemptsCtrl = TextEditingController();
  bool _initialized = false;
  bool _dispatchInitialized = false;
  bool _saving = false;
  bool _savingDispatch = false;

  @override
  void dispose() {
    _autoCtrl.dispose();
    _manualCtrl.dispose();
    _rescanIntervalCtrl.dispose();
    _maxRescanAttemptsCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(DriverAcceptSettings s) {
    _autoCtrl.text = s.autoAcceptSweepSeconds.toString();
    _manualCtrl.text = s.manualAcceptSweepSeconds.toString();
  }

  void _fillDispatchFrom(DriverDispatchSettings s) {
    _rescanIntervalCtrl.text = s.rescanIntervalSeconds.toString();
    _maxRescanAttemptsCtrl.text = s.maxRescanAttempts.toString();
  }

  Future<void> _saveDispatch(String? id) async {
    final interval = int.tryParse(_rescanIntervalCtrl.text.trim());
    final maxAttempts = int.tryParse(_maxRescanAttemptsCtrl.text.trim());
    if (interval == null || interval <= 0) {
      _showError('Thời gian quét lại không hợp lệ');
      return;
    }
    if (maxAttempts == null || maxAttempts <= 0) {
      _showError('Số lần quét trước khi báo admin không hợp lệ');
      return;
    }

    setState(() => _savingDispatch = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateDriverDispatchSettings(
            DriverDispatchSettings(
              id: id,
              rescanIntervalSeconds: interval,
              maxRescanAttempts: maxAttempts,
            ),
          );
      ref.invalidate(driverDispatchSettingsProvider);
      if (mounted) {
        _fillDispatchFrom(saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu thông số')));
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _savingDispatch = false);
    }
  }

  Future<void> _save(String? id) async {
    final auto = int.tryParse(_autoCtrl.text.trim());
    final manual = int.tryParse(_manualCtrl.text.trim());
    if (auto == null || auto <= 0) {
      _showError('Thời gian thanh chạy màu (khi bật) không hợp lệ');
      return;
    }
    if (manual == null || manual <= 0) {
      _showError('Thời gian thanh chạy màu (khi tắt) không hợp lệ');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateDriverAcceptSettings(
            DriverAcceptSettings(
              id: id,
              autoAcceptSweepSeconds: auto,
              manualAcceptSweepSeconds: manual,
            ),
          );
      ref.invalidate(driverAcceptSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu thông số')));
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
    final settingsAsync = ref.watch(driverAcceptSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thông số tài xế')),
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
                      'Áp dụng cho toàn sàn — điều khiển thanh trượt "Nhận đơn" ở màn nhận đơn '
                      'trong app tài xế, không cài riêng theo từng tài xế. Riêng biệt hoàn toàn '
                      'với "Thông số cửa hàng".',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Khi tài xế bật "Tự động nhận đơn"',
                      child: _NumberField(
                        controller: _autoCtrl,
                        label: 'Thời gian thanh chạy màu để nhận đơn (giây)',
                        helper:
                            'Ở màn nhận đơn, dải màu xanh chạy trên thanh trượt trong bấy nhiêu '
                            'giây. Hết giờ mà tài xế chưa trượt, hệ thống tự NHẬN đơn hộ.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Khi tài xế tắt "Tự động nhận đơn"',
                      child: _NumberField(
                        controller: _manualCtrl,
                        label: 'Thời gian thanh chạy màu để nhận đơn (giây)',
                        helper:
                            'Cùng vị trí thanh trượt như trên nhưng đổi màu cam. Hết giờ mà tài '
                            'xế chưa trượt, đơn tự CHUYỂN cho tài xế gần nhất tiếp theo. Nên đặt dài '
                            'hơn hẳn thời gian ở trên (mặc định 25 giây).',
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
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Quét tìm tài xế khi chưa có ai nhận',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Áp dụng khi đơn chuyển sang "Chờ tài xế lấy" mà không tìm được tài xế nào '
                      'online phù hợp — tự quét lại định kỳ, sau 1 số lần liên tiếp vẫn không có '
                      'ai thì báo admin quyết định huỷ đơn hay quét tiếp.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Consumer(
                      builder: (context, ref, _) {
                        final dispatchAsync = ref.watch(
                          driverDispatchSettingsProvider,
                        );
                        return dispatchAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => Text('Lỗi: $e'),
                          data: (s) {
                            if (!_dispatchInitialized) {
                              _fillDispatchFrom(s);
                              _dispatchInitialized = true;
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionCard(
                                  title: 'Nhịp quét lại',
                                  child: _NumberField(
                                    controller: _rescanIntervalCtrl,
                                    label: 'Bao lâu quét lại 1 lần (giây)',
                                    helper:
                                        'VD 30 hoặc 60 — cứ mỗi bấy nhiêu giây, hệ thống tự '
                                        'thử tìm tài xế online gần nhất 1 lần nữa.',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Ngưỡng báo admin',
                                  child: _NumberField(
                                    controller: _maxRescanAttemptsCtrl,
                                    label:
                                        'Quét mấy lần liên tiếp không có ai thì báo admin',
                                    helper:
                                        'VD 10 hoặc 20 — hết số lần này mà vẫn chưa có tài xế '
                                        'nào nhận, gửi thông báo cho admin chọn huỷ đơn hay quét '
                                        'tiếp (chọn quét tiếp sẽ tính lại từ đầu, đủ số lần này '
                                        'nữa thì báo lại).',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _savingDispatch
                                        ? null
                                        : () => _saveDispatch(s.id),
                                    child: _savingDispatch
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
                            );
                          },
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

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String helper;
  const _NumberField({
    required this.controller,
    required this.label,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

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
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
