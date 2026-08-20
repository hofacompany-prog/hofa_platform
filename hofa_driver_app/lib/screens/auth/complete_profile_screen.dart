import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_repository.dart';

/// Hiện khi đã đăng nhập Supabase Auth (SĐT này có thể đã có tài khoản ở role khác — vd khách
/// hàng) nhưng CHƯA có hồ sơ public.users role='driver' — xem router.dart +
/// hofa-db/90_multi_role_accounts.sql. Cùng pattern với hofa_customer_app.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await UserRepository().syncProfile(
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      ref.invalidate(userProfileProvider);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Hoàn tất hồ sơ',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Nhập thêm vài thông tin để bắt đầu đăng ký làm tài xế trên HOFA',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _fullNameCtrl,
                    decoration: const InputDecoration(labelText: 'Họ tên', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số điện thoại' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Tiếp tục'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading ? null : () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Đăng xuất'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
