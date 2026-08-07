import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/places_service.dart';

/// Kết quả trả về khi admin xác nhận 1 vị trí trên bản đồ.
class PickedLocation {
  final double latitude;
  final double longitude;
  final String line1;
  final String? ward;
  final String? district;
  final String province;

  PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
  });
}

const _defaultCenter = LatLng(
  10.7769,
  106.7009,
); // trung tâm TP.HCM — điểm khởi đầu hợp lý khi chưa có vị trí

/// Chọn vị trí chi nhánh bằng bản đồ (giống màn chọn vị trí bên app khách/cửa hàng):
/// ghim cố định giữa màn hình, kéo bản đồ hoặc tìm kiếm để di chuyển ghim, xác nhận là
/// xong. Dùng OpenStreetMap (flutter_map + Nominatim) — miễn phí, không cần API key.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _places = PlacesService();
  final _searchCtrl = TextEditingController();
  final _mapController = MapController();
  LatLng _center = _defaultCenter;
  Timer? _searchDebounce;
  Timer? _idleDebounce;
  List<ResolvedPlace> _predictions = [];
  ResolvedPlace? _selected;
  bool _resolving = false;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tryLocateMe(animate: false);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _idleDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// [userInitiated] = true khi bấm nút định vị (animate mặc định true) — lúc đó LUÔN
  /// thử hỏi lại quyền nếu chưa có (kể cả trước đó đã từ chối) và báo rõ cho biết nếu
  /// không lấy được vị trí, thay vì im lặng không làm gì. Áp dụng như nhau trên cả web
  /// lẫn app vì geolocator dùng chung 1 API cho mọi nền tảng.
  /// initState gọi với animate=false — vẫn im lặng, không làm phiền ngay lúc mở màn hình.
  Future<void> _tryLocateMe({bool animate = true}) async {
    final userInitiated = animate;
    try {
      if (userInitiated) {
        // Trình duyệt web không hỗ trợ kiểm tra riêng "dịch vụ định vị có bật không"
        // (geolocator_web không cài đặt method này) — coi như đang bật, để trình duyệt
        // tự xử lý qua bước xin quyền/lấy vị trí bên dưới thay vì báo lỗi oan.
        var serviceEnabled = true;
        try {
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
        } catch (_) {}
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Vui lòng bật định vị (GPS/vị trí) trên thiết bị để dùng tính năng này.',
                ),
              ),
            );
          }
          return;
        }
      }

      var permission = await Geolocator.checkPermission();
      var granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted &&
          (userInitiated || permission != LocationPermission.deniedForever)) {
        permission = await Geolocator.requestPermission();
        granted =
            permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      }
      if (!granted) {
        if (userInitiated && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == LocationPermission.deniedForever
                    ? 'HOFA chưa được cấp quyền vị trí — vào phần Cài đặt quyền của thiết bị/trình duyệt để bật lại.'
                    : 'Cần cấp quyền vị trí để định vị vị trí hiện tại.',
              ),
            ),
          );
        }
        return;
      }

      // geolocator_web (4.1.4) có lỗi đơn vị thời gian — truyền timeLimit dưới dạng mili-giây
      // thay vì đúng đơn vị nên trình duyệt hiểu 8 giây thành >2 tiếng. Tự giới hạn thời gian
      // chờ ở đây để không bị treo lâu bất thường khi trình duyệt (đặc biệt Safari) chậm trả
      // vị trí hoặc không trả lỗi rõ ràng.
      final pos =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Quá thời gian chờ xác định vị trí'),
          );
      final target = LatLng(pos.latitude, pos.longitude);
      _center = target;
      if (!mounted) return;
      if (animate) {
        _mapController.move(target, 16);
      } else {
        _resolveAddressAt(
          target,
        ); // bản đồ chưa dựng xong lúc initState — xác định địa chỉ ngay, không đợi sự kiện kéo bản đồ
      }
    } catch (_) {
      if (userInitiated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể lấy vị trí, vui lòng nhập hoặc kéo thả để lấy vị trí nhé!',
            ),
          ),
        );
      }
      // initState: im lặng, vẫn ở toạ độ mặc định, tự kéo bản đồ.
    }
  }

  void _onMapReady() {
    _resolveAddressAt(_center);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    // flutter_map không có sự kiện "camera idle" riêng như Google/Mapbox — tự debounce
    // để chỉ gọi reverse-geocode sau khi ngừng kéo bản đồ ~400ms, vừa mượt vừa tránh gọi
    // dồn dập vượt giới hạn tốc độ của Nominatim (1 request/giây).
    _idleDebounce?.cancel();
    _idleDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _resolveAddressAt(_center),
    );
  }

  Future<void> _resolveAddressAt(LatLng target) async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    final place = await _places.reverseGeocode(
      target.latitude,
      target.longitude,
    );
    if (!mounted) return;
    setState(() {
      _selected = place;
      _resolving = false;
      if (place == null) {
        _error =
            'Không xác định được địa chỉ ở vị trí này, thử kéo bản đồ sang chỗ khác.';
      }
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _predictions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searching = true);
      final results = await _places.autocomplete(
        value,
        lat: _center.latitude,
        lng: _center.longitude,
      );
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _searching = false;
      });
    });
  }

  void _selectPrediction(ResolvedPlace p) {
    setState(() {
      _predictions = [];
      _searchCtrl.text = p.formattedAddress;
      _selected = p;
      _center = LatLng(p.latitude, p.longitude);
    });
    _mapController.move(_center, 17);
  }

  void _confirm() {
    final place = _selected;
    if (place == null) return;
    Navigator.of(context).pop(
      PickedLocation(
        latitude: place.latitude,
        longitude: place.longitude,
        line1: place.line1,
        ward: place.ward,
        district: place.district,
        province: place.province ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Chọn vị trí trên bản đồ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm địa chỉ, tên đường...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_predictions.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _predictions.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(_predictions[i].formattedAddress),
                  onTap: () => _selectPrediction(_predictions[i]),
                ),
              ),
            )
          else
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 15,
                      onMapReady: _onMapReady,
                      onPositionChanged: _onPositionChanged,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hofa.hofa_admin',
                      ),
                    ],
                  ),
                  // Ghim cố định giữa màn hình — vị trí thật là tâm bản đồ, không phải marker gắn toạ độ.
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Icon(
                        Icons.location_pin,
                        size: 44,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'locate-me',
                      onPressed: () => _tryLocateMe(),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _resolving
                        ? 'Đang xác định địa chỉ...'
                        : (_error ??
                              _selected?.formattedAddress ??
                              'Kéo bản đồ hoặc tìm kiếm để chọn vị trí'),
                    style: TextStyle(
                      color: _error != null ? theme.colorScheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: (_selected == null || _resolving)
                        ? null
                        : _confirm,
                    child: const Text('Xác nhận vị trí này'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
