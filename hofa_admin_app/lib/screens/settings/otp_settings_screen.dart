import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/otp_settings.dart';
import '../../providers/admin_providers.dart';

/// Ngưỡng giá trị đơn để bắt buộc xác nhận OTP lấy hàng (cửa hàng-tài xế) và giao hàng (tài
/// xế-khách) — xem hofa-db/73_otp_threshold_settings.sql. Mặc định 0đ nghĩa là mọi đơn thật đều
/// vẫn bắt buộc OTP như trước (không tự ý nới lỏng an toàn cho tới khi admin chủ động đặt số).
class OtpSettingsScreen extends ConsumerStatefulWidget {
  const OtpSettingsScreen({super.key});

  @override
  ConsumerState<OtpSettingsScreen> createState() => _OtpSettingsScreenState();
}

class _OtpSettingsScreenState extends ConsumerState<OtpSettingsScreen> {
  final _amountCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _registrationOtpEnabled = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(OtpSettings s) {
    _amountCtrl.text = s.minOrderAmount.toString();
    _registrationOtpEnabled = s.registrationOtpEnabled;
  }

  Future<void> _save(OtpSettings current) async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 0) {
      _showError('Số tiền không hợp lệ');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateOtpSettings(
            OtpSettings(
              id: current.id,
              minOrderAmount: amount,
              registrationOtpEnabled: _registrationOtpEnabled,
            ),
          );
      ref.invalidate(otpSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu ngưỡng OTP')));
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
    final settingsAsync = ref.watch(otpSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ngưỡng OTP')),
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
                      'Đơn giá trị THẤP HƠN HOẶC BẰNG số tiền dưới đây bỏ qua xác nhận OTP hoàn '
                      'toàn — cả lúc tài xế lấy hàng ở cửa hàng lẫn lúc giao hàng cho khách. Đơn '
                      'vượt ngưỡng vẫn bắt buộc đúng mã như trước. Không áp dụng cho đơn mua hộ '
                      '(luôn bắt buộc ảnh xác nhận thay OTP).',
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
                              'Ngưỡng giá trị đơn',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _amountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                suffixText: 'đ',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mặc định 0đ — mọi đơn đều bắt buộc OTP (giữ nguyên như trước).',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: SwitchListTile(
                        title: const Text('Bắt nhập mã OTP lúc đăng ký'),
                        subtitle: const Text(
                          'Tắt = khách/cửa hàng/tài xế đăng ký xong vào thẳng, không phải nhập '
                          'mã xác thực (chưa nối SMS OTP thật nên mã hiện chỉ là số cố định).',
                        ),
                        value: _registrationOtpEnabled,
                        onChanged: (v) =>
                            setState(() => _registrationOtpEnabled = v),
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
