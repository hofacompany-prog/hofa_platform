import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Mã định danh phần cứng iOS (utsname.machine, vd "iPhone14,5") → tên thương mại quen thuộc
/// — Apple không có API trả thẳng tên này, phải tra bảng tĩnh. Chỉ phủ các đời máy còn phổ
/// biến; máy không có trong bảng rơi về IosDeviceInfo.name (tên người dùng tự đặt trong Cài
/// đặt, vẫn tốt hơn hẳn chuỗi "HOFA Store" cố định trước đây).
const _iosModelNames = {
  'iPhone8,1': 'iPhone 6s',
  'iPhone8,2': 'iPhone 6s Plus',
  'iPhone8,4': 'iPhone SE (2016)',
  'iPhone9,1': 'iPhone 7',
  'iPhone9,2': 'iPhone 7 Plus',
  'iPhone9,3': 'iPhone 7',
  'iPhone9,4': 'iPhone 7 Plus',
  'iPhone10,1': 'iPhone 8',
  'iPhone10,2': 'iPhone 8 Plus',
  'iPhone10,3': 'iPhone X',
  'iPhone10,4': 'iPhone 8',
  'iPhone10,5': 'iPhone 8 Plus',
  'iPhone10,6': 'iPhone X',
  'iPhone11,2': 'iPhone XS',
  'iPhone11,4': 'iPhone XS Max',
  'iPhone11,6': 'iPhone XS Max',
  'iPhone11,8': 'iPhone XR',
  'iPhone12,1': 'iPhone 11',
  'iPhone12,3': 'iPhone 11 Pro',
  'iPhone12,5': 'iPhone 11 Pro Max',
  'iPhone12,8': 'iPhone SE (2020)',
  'iPhone13,1': 'iPhone 12 mini',
  'iPhone13,2': 'iPhone 12',
  'iPhone13,3': 'iPhone 12 Pro',
  'iPhone13,4': 'iPhone 12 Pro Max',
  'iPhone14,2': 'iPhone 13 Pro',
  'iPhone14,3': 'iPhone 13 Pro Max',
  'iPhone14,4': 'iPhone 13 mini',
  'iPhone14,5': 'iPhone 13',
  'iPhone14,6': 'iPhone SE (2022)',
  'iPhone14,7': 'iPhone 14',
  'iPhone14,8': 'iPhone 14 Plus',
  'iPhone15,2': 'iPhone 14 Pro',
  'iPhone15,3': 'iPhone 14 Pro Max',
  'iPhone15,4': 'iPhone 15',
  'iPhone15,5': 'iPhone 15 Plus',
  'iPhone16,1': 'iPhone 15 Pro',
  'iPhone16,2': 'iPhone 15 Pro Max',
  'iPhone17,1': 'iPhone 16 Pro',
  'iPhone17,2': 'iPhone 16 Pro Max',
  'iPhone17,3': 'iPhone 16',
  'iPhone17,4': 'iPhone 16 Plus',
  'iPhone17,5': 'iPhone 16e',
};

/// Tên thiết bị dễ đọc để hiện ở màn "Thiết bị đăng nhập" (vd "iPhone 13", "samsung SM-G981B")
/// thay vì chuỗi cố định "HOFA Store" trước đây. Android không có API chính thức trả tên
/// thương mại (vd "Samsung Galaxy S20") — dùng "hãng + mã model" của device_info_plus, đủ để
/// phân biệt/nhận ra thiết bị dù không đẹp bằng tên thương mại.
Future<String> resolveDeviceName() async {
  if (kIsWeb) return 'Trình duyệt web';
  final plugin = DeviceInfoPlugin();
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final info = await plugin.iosInfo;
    final id = info.utsname.machine;
    return _iosModelNames[id] ?? info.name;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    final info = await plugin.androidInfo;
    return '${info.manufacturer} ${info.model}';
  }
  return 'HOFA Store';
}
