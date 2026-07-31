/// Lỗi trả về từ API HOFA — khớp với { ok:false, error:{code,message} } trong server/src/errors.js
class ApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  ApiException({required this.code, required this.message, required this.statusCode});

  @override
  String toString() => message;
}
