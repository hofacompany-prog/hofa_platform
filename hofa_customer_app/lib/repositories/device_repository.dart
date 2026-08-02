import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../core/api_client.dart';

const _deviceIdKey = 'hofa_customer_device_id';

/// Mã máy tự sinh, lưu cục bộ — chỉ để server phân biệt các thiết bị của cùng 1 tài
/// khoản (đăng xuất/đăng nhập lại vẫn cùng device_id), không cần chính xác tuyệt đối.
Future<String> _localDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_deviceIdKey);
  if (existing != null) return existing;
  final generated = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  await prefs.setString(_deviceIdKey, generated);
  return generated;
}

class DeviceRepository {
  final _api = ApiClient.instance;

  Future<void> registerPushToken(String pushToken) async {
    final deviceId = await _localDeviceId();
    await _api.post('/devices', body: {
      'device_id': deviceId,
      'device_name': 'HOFA Khách hàng',
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'push_token': pushToken,
    });
  }
}
