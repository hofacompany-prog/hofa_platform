import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

const _deviceIdKey = 'hofa_admin_device_id';

/// Mã máy tự sinh, lưu cục bộ — chỉ để server phân biệt các thiết bị của cùng 1 tài khoản
/// (đăng xuất/đăng nhập lại vẫn cùng device_id), không cần chính xác tuyệt đối.
Future<String> _localDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_deviceIdKey);
  if (existing != null) return existing;
  final generated = List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  await prefs.setString(_deviceIdKey, generated);
  return generated;
}

/// Đăng ký thiết bị nhận push cho admin — app admin chỉ chạy web nên không cần dò
/// merchants.max_devices (giới hạn đó chỉ áp cho merchant_owner/merchant_staff, xem
/// POST /devices ở server/src/routes/users.js) hay tên máy chi tiết (device_info_plus) như
/// 3 app kia, chỉ cần đăng ký token để nhận được push.
class DeviceRepository {
  final _api = ApiClient.instance;

  Future<void> registerPushToken(String pushToken) async {
    final deviceId = await _localDeviceId();
    await _api.post(
      '/devices',
      body: {
        'device_id': deviceId,
        'device_name': 'Trình duyệt web',
        'platform': 'web',
        'push_token': pushToken,
      },
    );
  }
}
