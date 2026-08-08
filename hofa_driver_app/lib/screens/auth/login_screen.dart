import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/phone_auth.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/app_version_text.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _isSignUp = false;
  bool _awaitingOtp = false; // đang ở bước nhập mã OTP (chỉ xảy ra lúc đăng ký)
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _fullNameCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_awaitingOtp) {
      await _confirmOtp();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    if (_isSignUp) {
      // Chưa nối SMS OTP thật — tạm hiện bước nhập mã, luôn chấp nhận 123123.
      // TODO: thay bằng gửi OTP thật qua supabase.auth.signInWithOtp(phone: ...) khi có provider SMS.
      setState(() {
        _awaitingOtp = true;
        _error = null;
        _info = 'Đã gửi mã xác thực tới ${_phoneCtrl.text.trim()}. Tạm thời dùng mã $kTempOtpCode.';
      });
      return;
    }

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
      setState(() => _error = e.message.contains('Invalid login credentials')
          ? 'Số điện thoại hoặc mật khẩu không đúng'
          : e.message);
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmOtp() async {
    if (_otpCtrl.text.trim() != kTempOtpCode) {
      setState(() => _error = 'Mã OTP không đúng');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: phoneToAuthEmail(_phoneCtrl.text.trim()),
        password: _passwordCtrl.text,
      );
      if (res.session == null) {
        setState(() => _error =
            'Không tạo được phiên đăng nhập. Cần tắt "Confirm email" trong Supabase Auth settings vì tài khoản dùng email nội bộ, không nhận được thư xác nhận thật.');
        return;
      }
      // Đảm bảo có hồ sơ public.users ngay — RegisterDriverScreen phía sau cần nó.
      await UserRepository().syncProfile(fullName: _fullNameCtrl.text.trim(), phone: _phoneCtrl.text.trim());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      Center(child: Image.asset('assets/images/logo.png', height: 64)),
                      const SizedBox(height: 12),
                      Text(
                        'HOFA cho tài xế',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _awaitingOtp
                            ? 'Xác thực số điện thoại'
                            : (_isSignUp ? 'Tạo tài khoản tài xế' : 'Đăng nhập để bắt đầu nhận đơn'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      if (_awaitingOtp) ...[
                        Text('Nhập mã OTP đã gửi tới ${_phoneCtrl.text.trim()}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otpCtrl,
                          decoration: const InputDecoration(labelText: 'Mã OTP'),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _submit(),
                        ),
                      ] else ...[
                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _fullNameCtrl,
                            decoration: const InputDecoration(labelText: 'Họ tên'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(labelText: 'Số điện thoại'),
                          keyboardType: TextInputType.phone,
                          validator: (v) => (v == null || !isValidPhone(v.trim())) ? 'Số điện thoại không hợp lệ' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: const InputDecoration(labelText: 'Mật khẩu'),
                          obscureText: true,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.length < 6) ? 'Mật khẩu tối thiểu 6 ký tự' : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 16),
                        Text(_info!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_awaitingOtp ? 'Xác nhận' : (_isSignUp ? 'Đăng ký' : 'Đăng nhập')),
                      ),
                      const SizedBox(height: 12),
                      if (_awaitingOtp)
                        TextButton(
                          onPressed: _loading ? null : () => setState(() => _awaitingOtp = false),
                          child: const Text('Quay lại'),
                        )
                      else
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _isSignUp = !_isSignUp;
                                    _error = null;
                                    _info = null;
                                  }),
                          child: Text(_isSignUp ? 'Đã có tài khoản? Đăng nhập' : 'Chưa có tài khoản? Đăng ký'),
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
