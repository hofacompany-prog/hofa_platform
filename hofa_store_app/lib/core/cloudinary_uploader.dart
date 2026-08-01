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
