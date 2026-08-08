import 'dart:html' as html;
import 'dart:typed_data';

/// Tải bytes về máy qua trình duyệt — dùng Blob URL (cùng origin) thay vì gán thẳng href="url
/// ngoài" vào thuộc tính download, vì trình duyệt phần lớn BỎ QUA thuộc tính download với URL
/// khác origin (ảnh VietQR nằm ở img.vietqr.io) — chỉ Blob URL mới ép tải xuống được chắc chắn.
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
