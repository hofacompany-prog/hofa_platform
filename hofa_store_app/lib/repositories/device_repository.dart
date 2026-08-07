import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_client.dart';
import '../core/device_session.dart';
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

  /// Đăng ký thiết bị nhận push. Với tài khoản cửa hàng (chủ/nhân viên), server chặn nếu
  /// cửa hàng đó đã đủ merchants.max_devices thiết bị — trả về [DeviceRegisterResult] báo
  /// "limit_reached" kèm thông tin thiết bị cũ nhất thay vì đăng ký thẳng, để gọi lại với
  /// [forceReplaceOldest] = true sau khi người dùng xác nhận gỡ thiết bị cũ đó.
  Future<DeviceRegisterResult> registerPushToken(
    String pushToken, {
    bool forceReplaceOldest = false,
  }) async {
    final deviceId = await _localDeviceId();
    final result = await _api.post(
      '/devices',
      body: {
        'device_id': deviceId,
        'device_name': 'HOFA Store',
        'platform': _currentPlatform(),
        'push_token': pushToken,
        if (forceReplaceOldest) 'force_replace_oldest': true,
      },
    );
    if (result is Map && result['status'] == 'limit_reached') {
      return DeviceRegisterResult.limitReached(result.cast<String, dynamic>());
    }
    final userId = Supabase.instance.client.auth.currentSession?.user.id;
    if (userId != null) DeviceSession.markRegistered(deviceId, userId);
    return const DeviceRegisterResult.ok();
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

/// Kết quả gọi POST /devices — [limitReached] = true nghĩa là server TỪ CHỐI đăng ký (chưa
/// tạo dòng mới) vì cửa hàng đã đủ số thiết bị tối đa, kèm thông tin thiết bị cũ nhất để hỏi
/// người dùng có muốn gỡ nó đi rồi đăng ký lại (forceReplaceOldest: true) hay không.
class DeviceRegisterResult {
  final bool limitReached;
  final int? maxDevices;
  final String? oldestDeviceName;
  final String? oldestDevicePlatform;
  final DateTime? oldestDeviceLastActive;

  const DeviceRegisterResult.ok()
    : limitReached = false,
      maxDevices = null,
      oldestDeviceName = null,
      oldestDevicePlatform = null,
      oldestDeviceLastActive = null;

  DeviceRegisterResult.limitReached(Map<String, dynamic> json)
    : limitReached = true,
      maxDevices = (json['max_devices'] as num?)?.toInt(),
      oldestDeviceName = (json['oldest_device'] as Map?)?['device_name'] as String?,
      oldestDevicePlatform = (json['oldest_device'] as Map?)?['platform'] as String?,
      oldestDeviceLastActive = DateTime.tryParse(
        '${(json['oldest_device'] as Map?)?['last_active_at']}',
      );
}
