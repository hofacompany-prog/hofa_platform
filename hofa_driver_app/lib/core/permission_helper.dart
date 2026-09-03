import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// 3 mức duy nhất cần phân biệt để quyết định hành động khi bấm nút: đã cấp (không cần làm gì
/// thêm), chưa quyết định (xin quyền lần đầu, trình duyệt/hệ thống tự hiện popup xin quyền), đã
/// từ chối (phải nhờ tự bật tay hoặc mở Cài đặt hệ thống).
enum PermissionState { granted, notDetermined, denied }

const _kNotificationGrantedKey = 'permission_notification_granted';
const _kLocationGrantedKey = 'permission_location_granted';

/// Dùng chung cho PermissionSettingsSection (màn Cá nhân) và popup nhắc cấp quyền lúc mở app
/// (home_screen.dart) — tránh trùng logic kiểm tra/xin quyền ở 2 nơi.
class PermissionHelper {
  PermissionHelper._();

  /// LUÔN thử hỏi hệ thống trước (để phát hiện đúng lúc quyền bị THU HỒI sau khi đã từng cấp —
  /// vd người dùng tự tắt lại trong cài đặt trình duyệt — mà hỏi lại), chỉ khi việc hỏi đó THẤT
  /// BẠI (lỗi/timeout thoáng qua lúc web mới khởi động) mới rơi về tin theo SharedPreferences đã
  /// lưu từ lần cấp gần nhất, tránh hỏi lại oan vì 1 lần kiểm tra bị trục trặc tạm thời.
  static Future<PermissionState> notificationState() async {
    final prefs = await SharedPreferences.getInstance();
    final live = await _liveNotificationState();
    if (live != null) {
      await prefs.setBool(_kNotificationGrantedKey, live == PermissionState.granted);
      return live;
    }
    return prefs.getBool(_kNotificationGrantedKey) == true
        ? PermissionState.granted
        : PermissionState.notDetermined;
  }

  /// null = không hỏi được hệ thống (lỗi/timeout) — khác với 1 kết quả xác định (kể cả denied).
  static Future<PermissionState?> _liveNotificationState() async {
    try {
      final status =
          (await FirebaseMessaging.instance.getNotificationSettings())
              .authorizationStatus;
      switch (status) {
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          return PermissionState.granted;
        case AuthorizationStatus.denied:
          return PermissionState.denied;
        default:
          // FCM báo "chưa quyết định" — kiểm tra thêm bằng permission_handler (đọc thẳng quyền hệ
          // thống Android qua ContextCompat, không qua lớp trung gian FCM hay bị trễ/báo sai trên
          // vài thiết bị) trước khi kết luận thật sự chưa cấp, tránh hiện popup xin quyền oan dù
          // người dùng đã bật rồi.
          if (kIsWeb) return PermissionState.notDetermined;
          final phStatus = await ph.Permission.notification.status;
          if (phStatus.isGranted || phStatus.isLimited) {
            return PermissionState.granted;
          }
          if (phStatus.isPermanentlyDenied) return PermissionState.denied;
          return PermissionState.notDetermined;
      }
    } catch (_) {
      return null;
    }
  }

  /// Cùng lý do notificationState() — luôn hỏi hệ thống trước để bắt được lúc quyền bị thu hồi.
  static Future<PermissionState> locationState() async {
    final prefs = await SharedPreferences.getInstance();
    final live = await _liveLocationState();
    if (live != null) {
      await prefs.setBool(_kLocationGrantedKey, live == PermissionState.granted);
      return live;
    }
    return prefs.getBool(_kLocationGrantedKey) == true
        ? PermissionState.granted
        : PermissionState.notDetermined;
  }

  static Future<PermissionState?> _liveLocationState() async {
    try {
      final permission = await Geolocator.checkPermission();
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          return PermissionState.granted;
        case LocationPermission.deniedForever:
          return PermissionState.denied;
        default:
          return PermissionState.notDetermined;
      }
    } catch (_) {
      return null;
    }
  }

  static Future<bool> tryOpenNativeSettings({required bool location}) async {
    try {
      return location
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Lối thoát khi quyền đã bị từ chối và tryOpenNativeSettings không tự mở được Cài đặt —
  /// trên web là do trình duyệt chặn (giới hạn bảo mật nền tảng), gần như không xảy ra trên
  /// native (openAppSettings() luôn mở được Cài đặt hệ thống thật), chỉ còn là lối thoát dự
  /// phòng hiếm gặp.
  static void showManualInstructions(BuildContext context, String label) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bật quyền $label'),
        content: Text(
          kIsWeb
              ? 'Trình duyệt không cho web tự mở cài đặt quyền — bạn tự bật giúp:\n\n'
                    '1. Nhấn vào biểu tượng ổ khoá (hoặc chữ "i") cạnh thanh địa chỉ trình duyệt.\n'
                    '2. Chọn "Quyền của trang web" (Site settings).\n'
                    '3. Bật lại quyền $label cho trang này.\n'
                    '4. Tải lại trang.'
              : 'Không tự mở được Cài đặt — bạn tự vào Cài đặt máy > Ứng dụng > tìm app này > '
                    'bật lại quyền $label giúp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  /// Quyền chưa quyết định → bật popup xin quyền của trình duyệt/hệ thống, ghi nhớ nếu vừa được
  /// cấp. Quyền đã có → thử mở thẳng Cài đặt hệ thống để xem/chỉnh thêm (chỉ mở được thật trên
  /// bản cài native). Quyền đã bị từ chối/web không mở được cài đặt → chỉ dẫn tay.
  static Future<void> requestNotification(BuildContext context) async {
    final state = await notificationState();
    if (state != PermissionState.notDetermined) {
      final opened = await tryOpenNativeSettings(location: false);
      if (!opened && context.mounted) {
        showManualInstructions(context, 'thông báo');
      }
      return;
    }
    await FirebaseMessaging.instance.requestPermission();
    final after = await _liveNotificationState();
    if (after != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationGrantedKey, after == PermissionState.granted);
    }
  }

  static Future<void> requestLocation(BuildContext context) async {
    final state = await locationState();
    if (state != PermissionState.notDetermined) {
      final opened = await tryOpenNativeSettings(location: true);
      if (!opened && context.mounted) {
        showManualInstructions(context, 'vị trí');
      }
      return;
    }
    await Geolocator.requestPermission();
    final after = await _liveLocationState();
    if (after != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLocationGrantedKey, after == PermissionState.granted);
    }
  }

  // ---------------------------------------------------------------------------------------
  // Nhắc lại quyền đã bị từ chối, sau N ngày admin cấu hình (app_update_settings, xem
  // hofa-db/102_permission_reprompt_settings.sql) — CHỈ hiện banner nhắc nhẹ, tự đóng được, KHÔNG
  // tự mở Cài đặt hay chặn màn hình. Apple đã từ chối app vì coi việc tự động điều hướng/chặn lặp
  // lại là ép buộc (guideline 5.1.1(iv), 4.5.4) — banner này chỉ gợi ý, người dùng chủ động bấm
  // "Mở Cài đặt" thì mới mở, bấm "Đóng" thì thôi hẳn tới lần nhắc kế tiếp.
  // ---------------------------------------------------------------------------------------
  static const _kNotifLastAskedKey = 'permission_notification_last_asked_at';
  static const _kLocationLastAskedKey = 'permission_location_last_asked_at';
  static Map<String, dynamic>? _cachedSettings;

  static Future<Map<String, dynamic>?> _repromptSettings() async {
    if (_cachedSettings != null) return _cachedSettings;
    try {
      final res = await ApiClient.instance.get('/app-update-settings');
      if (res is Map<String, dynamic>) _cachedSettings = res;
    } catch (_) {
      // mất mạng/lỗi tạm thời — coi như chưa cấu hình, không nhắc, thử lại lần mở app sau.
    }
    return _cachedSettings;
  }

  /// Ghi lại mốc "vừa hỏi/nhắc" — gọi ngay sau khi hiện hộp thoại xin quyền lần đầu HOẶC sau khi
  /// hiện banner nhắc, để N ngày tiếp theo tính từ đúng lần cuối cùng người dùng thấy nó.
  static Future<void> markAsked({required bool location}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      location ? _kLocationLastAskedKey : _kNotifLastAskedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> _dueForReminder(String key, int days) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(key);
    if (lastMs == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last).inDays >= days;
  }

  /// Gọi mỗi lần mở Trang chủ, SAU khi đã qua bước hỏi lần đầu (notDetermined) — nếu quyền đang bị
  /// từ chối và đã đủ N ngày theo cấu hình admin, hiện banner nhắc nhẹ (không chặn, tự đóng được).
  static Future<void> maybeRemind(
    BuildContext context, {
    required bool location,
  }) async {
    final state = location ? await locationState() : await notificationState();
    if (state != PermissionState.denied) return;
    final settings = await _repromptSettings();
    final days = (settings?[location ? 'location_reprompt_days' : 'notif_reprompt_days'] as num?)
        ?.toInt();
    if (days == null) return;
    final due = await _dueForReminder(
      location ? _kLocationLastAskedKey : _kNotifLastAskedKey,
      days,
    );
    if (!due || !context.mounted) return;
    await markAsked(location: location);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          location
              ? 'Bạn chưa bật quyền vị trí — bật để xác định đúng vị trí chi nhánh.'
              : 'Bạn chưa bật thông báo — bật để không lỡ đơn mới.',
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              tryOpenNativeSettings(location: location);
            },
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
  }
}
