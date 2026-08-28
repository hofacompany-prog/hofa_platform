import 'package:flutter/foundation.dart' show kIsWeb;
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
}
