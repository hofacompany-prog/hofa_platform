import 'file_download_stub.dart' if (dart.library.html) 'file_download_web.dart' as impl;

/// Tải 1 file về máy qua trình duyệt (vd ảnh QR) — no-op ngoài web, xem file_download_stub.dart.
class FileDownloadService {
  static Future<void> downloadBytes(List<int> bytes, String filename) => impl.downloadBytes(bytes, filename);
}
