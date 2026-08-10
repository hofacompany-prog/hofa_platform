import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

/// Mở chỉ đường tới (lat, lng) — ưu tiên intent riêng của app bản đồ (google.navigation:/geo:
/// trên Android, maps://apple.com trên iOS) thay vì link web thường
/// (https://www.google.com/maps/...). Trước đây chỉ dùng link web: nếu máy không có app Maps
/// nào được đặt làm trình xử lý https mặc định, Android/Chrome mở nó trong tab trình duyệt
/// thường — bấm back sau đó không thoát hẳn app mà dừng lại ở 1 tab trống của Chrome ("Tìm hoặc
/// nhập tên trang web").
Future<void> launchDirections(double lat, double lng) async {
  if (!kIsWeb) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final googleNav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      if (await canLaunchUrl(googleNav)) {
        await launchUrl(googleNav, mode: LaunchMode.externalApplication);
        return;
      }
      final geo = Uri.parse('geo:0,0?q=$lat,$lng');
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
        return;
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final appleMaps = Uri.parse(
        'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d',
      );
      if (await canLaunchUrl(appleMaps)) {
        await launchUrl(appleMaps, mode: LaunchMode.externalApplication);
        return;
      }
    }
  }
  final fallback = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
  );
  if (kIsWeb) {
    // Bản web (kể cả PWA đã "Thêm vào MH chính" trên iOS) — LaunchMode.externalApplication ứng
    // với window.open mở TAB/CỬA SỔ MỚI, tách hẳn khỏi tab đang chạy app nên không có lịch sử gì
    // để quay lại; bấm back kẹt ở đúng trang trống đó ("Tìm hoặc nhập tên trang web"). Điều
    // hướng NGAY TRONG cùng tab (webOnlyWindowName: '_self') thay vì mở tab mới — bấm back lúc
    // này quay lại đúng lịch sử duyệt web, tức là quay thẳng về app, không còn trang nào để kẹt.
    await launchUrl(fallback, webOnlyWindowName: '_self');
    return;
  }
  if (await canLaunchUrl(fallback)) {
    await launchUrl(fallback, mode: LaunchMode.externalApplication);
  }
}
