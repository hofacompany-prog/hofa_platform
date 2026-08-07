import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'device_session.dart';
import 'env.dart';
import 'api_exception.dart';

/// Gọi API HOFA (server/src/routes/*.js) — tự đính kèm access_token của phiên
/// Supabase hiện tại (nếu có) qua header Authorization: Bearer <token>.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

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
    // Thiết bị này vừa bị chủ/nhân viên khác hoặc admin gỡ khỏi tài khoản (màn "Thiết bị
    // đăng nhập") — server chặn ngay từ request này, phía app phải tự đăng xuất + xoá session
    // Supabase cục bộ ngay lập tức, không chờ người dùng tự nhận ra rồi thao tác gì thêm.
    if (code == 'DEVICE_REVOKED') {
      DeviceSession.clear();
      Supabase.instance.client.auth.signOut();
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
