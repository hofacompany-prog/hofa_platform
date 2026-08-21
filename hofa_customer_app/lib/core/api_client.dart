import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show navigatorKey;
import 'device_session.dart';
import 'env.dart';
import 'api_exception.dart';

/// Gọi API HOFA (server/src/routes/*.js) — tự đính kèm access_token của phiên
/// Supabase hiện tại (nếu có) qua header Authorization: Bearer <token>.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // Nhiều request cùng lúc có thể đều dính DEVICE_REVOKED (vd vài lời gọi API song song lúc
  // mở màn hình) — chặn hiện popup chồng popup, chỉ 1 cái duy nhất mỗi lần bị gỡ.
  bool _showingRevokedDialog = false;

  void _showDeviceRevokedDialog() {
    if (_showingRevokedDialog) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _showingRevokedDialog = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Thiết bị đã bị gỡ'),
        content: const Text(
          'Thiết bị này vừa bị gỡ khỏi danh sách thiết bị đăng nhập của tài khoản (do admin '
          'thực hiện). Hãy đăng nhập lại để tiếp tục sử dụng.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              GoRouter.of(context).go('/login');
            },
            child: const Text('Đăng nhập lại'),
          ),
        ],
      ),
    ).then((_) => _showingRevokedDialog = false);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final base = Uri.parse(Env.apiBaseUrl);
    return base.replace(
      path: '${base.path}/$clean'.replaceAll('//', '/'),
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, String> _headers() {
    final session = Supabase.instance.client.auth.currentSession;
    final deviceId = DeviceSession.headerFor(session?.user.id);
    return {
      'Content-Type': 'application/json',
      // Server chỉ trả đúng hồ sơ role của app Khách (dù cùng SĐT có thể còn hồ sơ role khác
      // — vd cũng là tài xế), xem server/src/middleware/auth.js + hofa-db/90_multi_role_accounts.sql.
      'X-App-Scope': 'customer',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      if (deviceId != null) 'X-Device-Id': deviceId,
    };
  }

  dynamic _handle(http.Response resp) {
    Map<String, dynamic> body;
    try {
      body = resp.body.isEmpty ? {} : jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(code: 'BAD_RESPONSE', message: 'Phản hồi không đúng định dạng', statusCode: resp.statusCode);
    }
    if (body['ok'] == true) return body['data'];
    final err = body['error'] as Map<String, dynamic>? ?? {};
    final code = err['code']?.toString() ?? 'UNKNOWN';
    // Thiết bị này vừa bị admin gỡ khỏi tài khoản (màn "Thiết bị đăng nhập") — server chặn
    // ngay từ request này, phía app phải tự đăng xuất + xoá session Supabase cục bộ ngay lập
    // tức, không chờ khách tự nhận ra rồi thao tác gì thêm.
    if (code == 'DEVICE_REVOKED') {
      DeviceSession.clear();
      Supabase.instance.client.auth.signOut();
      _showDeviceRevokedDialog();
    }
    throw ApiException(
      code: code,
      message: err['message']?.toString() ?? 'Lỗi không xác định',
      statusCode: resp.statusCode,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final resp = await http.get(_uri(path, query), headers: _headers());
    return _handle(resp);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final resp = await http.post(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(resp);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final resp = await http.patch(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(resp);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final resp = await http.put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(resp);
  }

  Future<dynamic> delete(String path) async {
    final resp = await http.delete(_uri(path), headers: _headers());
    return _handle(resp);
  }
}
