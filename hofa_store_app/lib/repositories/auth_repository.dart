import '../core/api_client.dart';

class AuthRepository {
  final _api = ApiClient.instance;

  /// Quên mật khẩu — đổi thẳng mật khẩu Supabase Auth qua server (Service Role key), không
  /// cần biết mật khẩu cũ. [newPassword] bỏ trống thì server tự reset về "123123" (xem
  /// server/src/routes/auth.js).
  Future<void> forgotPassword({
    required String phone,
    String? newPassword,
  }) async {
    await _api.post(
      '/auth/forgot-password',
      body: {
        'phone': phone,
        if (newPassword != null && newPassword.isNotEmpty)
          'new_password': newPassword,
      },
    );
  }
}
