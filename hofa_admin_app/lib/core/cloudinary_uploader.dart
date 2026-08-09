import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// Upload ảnh lên Cloudinary bằng chữ ký lấy từ server (server giữ API_SECRET,
/// xem server/src/routes/uploads.js) — client không bao giờ cầm secret.
class CloudinaryUploader {
  final _api = ApiClient.instance;

  Future<String> uploadImage(Uint8List bytes, String filename, {required String folder}) async {
    final sig = await _api.post('/uploads/cloudinary-signature', body: {'folder': folder}) as Map<String, dynamic>;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/${sig['cloud_name']}/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = sig['api_key'].toString()
      ..fields['timestamp'] = sig['timestamp'].toString()
      ..fields['signature'] = sig['signature'].toString()
      ..fields['folder'] = sig['folder'].toString()
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('Cloudinary từ chối upload: $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['secure_url'] as String;
  }
}

/// Chèn transform "xuất ra PNG" vào URL Cloudinary — dùng cho icon tabbar: tải lên SVG gốc
/// (từ thư viện Lucide) nhưng luôn PHÁT ra PNG, để 3 app khách/cửa hàng/tài xế chỉ cần
/// Image.network như mọi ảnh khác, không cần thêm gói flutter_svg. Cloudinary tự rasterize
/// SVG sang PNG phía server theo transform này, không đụng gì tới ảnh gốc đã lưu.
String toCloudinaryPngUrl(String secureUrl) {
  const marker = '/image/upload/';
  final i = secureUrl.indexOf(marker);
  if (i < 0) return secureUrl;
  final insertAt = i + marker.length;
  return '${secureUrl.substring(0, insertAt)}f_png,q_auto/${secureUrl.substring(insertAt)}';
}
