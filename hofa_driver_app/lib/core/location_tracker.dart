import 'package:geolocator/geolocator.dart';

/// Chỉ lấy vị trí TỪNG LẦN theo đúng lúc tài xế chủ động thao tác (bật online, xác nhận "Đã lấy
/// hàng"/"Đã giao xong") — KHÔNG còn theo dõi liên tục (đã bỏ Geolocator.getPositionStream nền
/// trước đây) để tránh vướng chính sách "theo dõi vị trí thời gian thực" của Apple/Google, đúng
/// hành vi của bản PWA cũ.
class LocationTracker {
  LocationTracker._();
  static final LocationTracker instance = LocationTracker._();

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<Position?> current() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }
}
