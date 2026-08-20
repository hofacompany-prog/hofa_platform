import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      // Bắt buộc trên mọi request kể từ khi middleware yêu cầu — admin đăng nhập email/mật
      // khẩu riêng, không đi qua luồng đa role cùng SĐT, nhưng vẫn phải khai báo scope.
      'X-App-Scope': 'admin',
      if (token != null) 'Authorization': 'Bearer $token',
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
    throw ApiException(
      code: err['code']?.toString() ?? 'UNKNOWN',
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

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) async {
    final resp = await http.delete(_uri(path, query), headers: _headers());
    return _handle(resp);
  }
}
