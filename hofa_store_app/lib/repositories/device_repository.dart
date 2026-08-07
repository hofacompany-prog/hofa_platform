import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../core/api_client.dart';
import '../models/user_device.dart';

/// kIsWeb PHẢI kiểm tra trước — defaultTargetPlatform trên web vẫn trả về iOS/Android
/// theo User-Agent trình duyệt, không phải giá trị 'web' riêng, dễ ghi nhầm platform.
String _currentPlatform() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

const _deviceIdKey = 'hofa_store_device_id';

/// Mã máy tự sinh, lưu cục bộ — chỉ để server phân biệt các thiết bị của cùng 1 tài
/// khoản (đăng xuất/đăng nhập lại vẫn cùng device_id), không cần chính xác tuyệt đối.
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

class DeviceRepository {
  final _api = ApiClient.instance;

  Future<void> registerPushToken(String pushToken) async {
    final deviceId = await _localDeviceId();
    await _api.post(
      '/devices',
      body: {
        'device_id': deviceId,
        'device_name': 'HOFA Store',
        'platform': _currentPlatform(),
        'push_token': pushToken,
      },
    );
  }

  /// Mã máy cục bộ hiện tại — dùng để đánh dấu "Thiết bị này" trong màn danh sách
  /// thiết bị (so với device_id server trả về), không expose ra ngoài bằng cách nào khác.
  Future<String> currentDeviceId() => _localDeviceId();

  Future<List<UserDevice>> list() async {
    final data = await _api.get('/devices') as List;
    return data
        .map((e) => UserDevice.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
  }

  Future<void> remove(String id) => _api.delete('/devices/$id');
}
