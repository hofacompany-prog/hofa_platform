import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Theo dõi vị trí khi tài xế đang online/đang chạy đơn — chỉ hoạt động khi app
/// đang mở (foreground). Cần thêm 1 background service riêng (vd flutter_background_service)
/// nếu muốn app tiếp tục gửi vị trí khi bị thu nhỏ hẳn hoặc tắt màn hình lâu — nằm
/// ngoài phạm vi bản v1 này.
class LocationTracker {
  LocationTracker._();
  static final LocationTracker instance = LocationTracker._();

  StreamSubscription<Position>? _sub;

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

  bool get isTracking => _sub != null;

  Future<bool> start(void Function(Position) onUpdate) async {
    if (!await ensurePermission()) return false;
    stop();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 30),
    ).listen(onUpdate);
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
