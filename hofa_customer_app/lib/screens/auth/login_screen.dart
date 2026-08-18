import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_error.dart';
import '../../core/phone_auth.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/app_version_text.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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
      // Chưa nối SMS OTP thật — tạm hiện bước nhập mã, luôn chấp nhận "123123". Admin bật/tắt
      // bước này qua otp_settings.registration_otp_enabled (hofa-db/76_registration_otp_toggle.sql)
      // — tắt thì gọi thẳng _confirmOtp() (tự bỏ qua kiểm tra mã vì đọc cùng cờ này).
      // TODO: thay bằng gửi OTP thật qua supabase.auth.signInWithOtp(phone: ...) khi có provider SMS.
      if (!_registrationOtpEnabled) {
        await _confirmOtp();
        return;
      }
      setState(() {
        _awaitingOtp = true;
        _error = null;
        _info =
            'Đã gửi mã xác thực tới $_phoneDisplay. Tạm thời dùng mã 123123.';
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
      // Báo trình duyệt "form đã nộp xong" — đây là lúc Chrome/Safari thật sự bật popup "Lưu
      // mật khẩu?" trên web, chỉ gắn autofillHints thôi chưa đủ để tự bật popup này.
      TextInput.finishAutofillContext();
    } on AuthException catch (e) {
      setState(() => _error = translateAuthError(e));
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _phoneDisplay => _phoneCtrl.text.trim();

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

  bool get _registrationOtpEnabled =>
      ref.read(otpSettingsProvider).valueOrNull?.registrationOtpEnabled ??
      false;

  Future<void> _confirmOtp() async {
    if (_registrationOtpEnabled && _otpCtrl.text.trim() != '123123') {
      setState(() => _error = 'Mã OTP không đúng');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    // Chặn router.dart tự đá qua /complete-profile ngay khi signUp() vừa tạo session (auth
    // state đổi trước khi /me/sync bên dưới kịp chạy xong) — không thì bắt nhập lại họ
    // tên/SĐT lần 2 ở màn đó. Tắt lại ở finally dù thành công hay lỗi.
    ref.read(authFlowInProgressProvider.notifier).state = true;
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: phoneToAuthEmail(_phoneCtrl.text.trim()),
        password: _passwordCtrl.text,
      );
      if (res.session == null) {
        setState(
          () => _error =
              'Không tạo được phiên đăng nhập. Cần tắt "Confirm email" trong Supabase Auth settings vì tài khoản dùng email nội bộ, không nhận được thư xác nhận thật.',
        );
        return;
      }
      await ref
          .read(userRepoProvider)
          .syncProfile(
            fullName: _fullNameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
          );
      ref.invalidate(userProfileProvider);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Đăng ký thành công!'),
          content: const Text(
            'Chào mừng bạn đến với HOFA — bắt đầu đặt hàng ngay thôi.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Bắt đầu'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() => _error = translateAuthError(e));
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      ref.read(authFlowInProgressProvider.notifier).state = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(
      otpSettingsProvider,
    ); // kích hoạt fetch sớm để có kịp khi bấm Đăng ký
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
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/logo.png', height: 64),
                          const SizedBox(height: 16),
                          Text(
                            'HOFA',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _awaitingOtp
                                ? 'Xác thực số điện thoại'
                                : (_isSignUp
                                      ? 'Tạo tài khoản để bắt đầu đặt hàng'
                                      : 'Đăng nhập để đặt hàng'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 32),
                          if (_awaitingOtp) ...[
                            Text(
                              'Nhập mã OTP đã gửi tới $_phoneDisplay',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _otpCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Mã OTP',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _submit(),
                            ),
                          ] else ...[
                            // AutofillGroup + autofillHints đúng cặp username/password (kể cả
                            // khi định danh thật là SĐT — trình duyệt chỉ nhận diện "sẽ lưu mật
                            // khẩu" qua các hint chuẩn này) để Chrome/Safari tự bật hỏi "Lưu mật
                            // khẩu?" sau khi đăng nhập/đăng ký thành công, lần sau khỏi gõ lại.
                            AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSignUp) ...[
                                    TextFormField(
                                      controller: _fullNameCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Họ tên',
                                        border: OutlineInputBorder(),
                                      ),
                                      autofillHints: const [AutofillHints.name],
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Nhập họ tên'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  TextFormField(
                                    controller: _phoneCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Số điện thoại',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.phone,
                                    autofillHints: [
                                      _isSignUp
                                          ? AutofillHints.newUsername
                                          : AutofillHints.username,
                                    ],
                                    validator: (v) =>
                                        (v == null || !isValidPhone(v.trim()))
                                        ? 'Số điện thoại không hợp lệ'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Mật khẩu',
                                      border: OutlineInputBorder(),
                                    ),
                                    obscureText: true,
                                    autofillHints: [
                                      _isSignUp
                                          ? AutofillHints.newPassword
                                          : AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) => _submit(),
                                    validator: (v) =>
                                        (v == null || v.length < 6)
                                        ? 'Mật khẩu tối thiểu 6 ký tự'
                                        : null,
                                  ),
                                  if (!_isSignUp)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _loading
                                            ? null
                                            : _forgotPassword,
                                        child: const Text('Quên mật khẩu?'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          if (_info != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _info!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
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
                                : Text(
                                    _awaitingOtp
                                        ? 'Xác nhận'
                                        : (_isSignUp ? 'Đăng ký' : 'Đăng nhập'),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          if (_awaitingOtp)
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(() => _awaitingOtp = false),
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
                              child: Text(
                                _isSignUp
                                    ? 'Đã có tài khoản? Đăng nhập'
                                    : 'Chưa có tài khoản? Đăng ký',
                              ),
                            ),
                        ],
                      ),
                    ),
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
