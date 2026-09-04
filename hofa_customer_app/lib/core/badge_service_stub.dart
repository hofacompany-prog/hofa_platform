import 'package:app_badge_plus/app_badge_plus.dart';

/// Android/iOS thật (khác PWA/web dùng Badging API) — app_badge_plus gọi thẳng API native nên
/// badge xoá NGAY khi gọi, không phải chờ push tiếp theo. isSupported() tự kiểm tra launcher/OS
/// có hỗ trợ không (nhiều launcher Android không có badge) — không hỗ trợ thì bỏ qua êm.
Future<void> setBadge(int count) async {
  try {
    if (!await AppBadgePlus.isSupported()) return;
    await AppBadgePlus.updateBadge(count);
  } catch (_) {}
}
