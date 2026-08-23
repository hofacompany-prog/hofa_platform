import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Đã từng xác nhận CẤP RỒI (lưu SharedPreferences) thì tin luôn, KHÔNG hỏi lại hệ thống mỗi
  /// lần mở app nữa — vừa tránh phiền khi quyền thật sự đã có, vừa tránh trường hợp
  /// getNotificationSettings()/checkPermission() lỡ chậm/lỗi thoáng qua lúc web mới khởi động
  /// khiến tưởng nhầm là chưa cấp (rơi về notDetermined ở nhánh catch) rồi hỏi lại oan. Chỉ khi
  /// CHƯA từng lưu "đã cấp" mới thật sự hỏi hệ thống — cấp rồi thì ghi nhớ luôn từ đây.
  static Future<PermissionState> notificationState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kNotificationGrantedKey) == true) {
      return PermissionState.granted;
    }
    final state = await _liveNotificationState();
    if (state == PermissionState.granted) {
      await prefs.setBool(_kNotificationGrantedKey, true);
    }
    return state;
  }

  static Future<PermissionState> _liveNotificationState() async {
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
          return PermissionState.notDetermined;
      }
    } catch (_) {
      return PermissionState.notDetermined;
    }
  }

  /// Cùng lý do notificationState() — quyền vị trí đã xác nhận cấp thì nhớ luôn, không hỏi lại.
  static Future<PermissionState> locationState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kLocationGrantedKey) == true) {
      return PermissionState.granted;
    }
    final state = await _liveLocationState();
    if (state == PermissionState.granted) {
      await prefs.setBool(_kLocationGrantedKey, true);
    }
    return state;
  }

  static Future<PermissionState> _liveLocationState() async {
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
      return PermissionState.notDetermined;
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

  /// Trình duyệt không cho web tự mở bảng cài đặt quyền (giới hạn bảo mật nền tảng) — đây là lối
  /// thoát duy nhất khi quyền đã bị từ chối và tryOpenNativeSettings không hoạt động (web).
  static void showManualInstructions(BuildContext context, String label) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bật quyền $label'),
        content: Text(
          'Trình duyệt không cho web tự mở cài đặt quyền — bạn tự bật giúp:\n\n'
          '1. Nhấn vào biểu tượng ổ khoá (hoặc chữ "i") cạnh thanh địa chỉ trình duyệt.\n'
          '2. Chọn "Quyền của trang web" (Site settings).\n'
          '3. Bật lại quyền $label cho trang này.\n'
          '4. Tải lại trang.',
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
  /// cấp. Quyền đã có (kể cả từ cache) → thử mở thẳng Cài đặt hệ thống để xem/chỉnh thêm (chỉ mở
  /// được thật trên bản cài native). Quyền đã bị từ chối/web không mở được cài đặt → chỉ dẫn tay.
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
    if (after == PermissionState.granted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationGrantedKey, true);
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
    if (after == PermissionState.granted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLocationGrantedKey, true);
    }
  }
}
