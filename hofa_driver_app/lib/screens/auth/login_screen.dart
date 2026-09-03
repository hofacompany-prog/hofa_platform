import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_error.dart';
import '../../core/phone_auth.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/app_version_text.dart';

/// CHỈ đăng nhập — không còn tự đăng ký trong app. Tài khoản tài xế do admin tạo sẵn (đủ điều
/// kiện lên App Store/CH Play: apps không tự cho tạo tài khoản thì không bắt buộc phải có nút
/// xoá tài khoản trong app), tài xế chỉ nhận SĐT/mật khẩu từ admin rồi đăng nhập ở đây — vào
/// trong mới điền hồ sơ (RegisterDriverScreen, xem router.dart) nếu chưa từng điền.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: phoneToAuthEmail(_phoneCtrl.text.trim()),
        password: _passwordCtrl.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = translateAuthError(e));
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Chưa nối SMS OTP thật nên không xác minh gì thêm ngoài đúng SĐT đã đăng ký, khớp mức xác
  /// thực hiện có của cả hệ thống (xem server/src/routes/auth.js). Reset thẳng, không cần biết
  /// mật khẩu cũ.
  Future<void> _forgotPassword() async {
    final phone = _phoneCtrl.text.trim();
    if (!isValidPhone(phone)) {
      setState(
        () => _error =
            'Nhập đúng số điện thoại ở trên trước khi bấm "Quên mật khẩu"',
      );
      return;
    }
    final newPasswordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quên mật khẩu?'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  // Đọc thẳng từ Theme thay vì DefaultTextStyle.of(context) (ambient, có thể bị
                  // 1 ancestor nào đó ghi đè bất ngờ) — cứng cỡ chữ/font/màu đen, không phụ thuộc
                  // widget cha, để chắc chắn hiện đúng cỡ thường, không đậm, không gạch chân.
                  style:
                      Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ) ??
                      const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                  children: [
                    const TextSpan(text: 'Mật khẩu sẽ được reset về '),
                    TextSpan(
                      text: '123123',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.secondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const TextSpan(
                      text: ' nếu bạn không nhập mật khẩu mới bên dưới.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final newPassword = newPasswordCtrl.text.trim();
      await AuthRepository().forgotPassword(
        phone: phone,
        newPassword: newPassword,
      );
      if (mounted) {
        setState(
          () => _info = newPassword.isEmpty
              ? 'Đã đặt lại mật khẩu về 123123 — đăng nhập lại bằng mật khẩu này.'
              : 'Đã đặt mật khẩu mới — đăng nhập lại bằng mật khẩu vừa đặt.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Không cho Scaffold co lại theo bàn phím — nếu không Positioned(bottom:) của
      // AppVersionText bên dưới tính theo mép dưới ĐÃ BỊ ĐẨY LÊN, làm chữ phiên bản trôi
      // lên theo bàn phím và đè vào các ô nhập phía trên. SingleChildScrollView bên trong
      // vẫn tự cuộn ô đang gõ lên trên bàn phím bình thường dù tắt cờ này.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Center(
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 64,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'HOFA cho tài xế',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Đăng nhập để bắt đầu nhận đơn',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại',
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || !isValidPhone(v.trim()))
                            ? 'Số điện thoại không hợp lệ'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                        ),
                        obscureText: true,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Mật khẩu tối thiểu 6 ký tự'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _info!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Đăng nhập'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: AppVersionText(),
          ),
        ],
      ),
    );
  }
}
