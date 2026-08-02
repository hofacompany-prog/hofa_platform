import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ResolvedPlace {
  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String line1;
  final String? ward;
  final String? district;
  final String? province;

  ResolvedPlace({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.line1,
    this.ward,
    this.district,
    this.province,
  });
}

/// Tra cứu địa chỉ bằng Nominatim (https://nominatim.org) — API tìm kiếm/geocode miễn
/// phí của OpenStreetMap, không cần API key. Theo đúng usage policy của họ
/// (https://operations.osmfoundation.org/policies/nominatim/): phải gửi kèm User-Agent
/// định danh app, và không gọi dồn dập (đã debounce 350ms ở màn hình chọn địa chỉ) —
/// đủ dùng cho MVP, nếu lượng truy cập lớn về sau nên đổi sang 1 nhà cung cấp trả phí.
class PlacesService {
  static const _base = 'https://nominatim.openstreetmap.org';
  static const _headers = {'User-Agent': 'HofaApp/1.0 (hofacompany@gmail.com)'};

  bool get isConfigured => true; // Nominatim không cần cấu hình gì cả

  Future<List<ResolvedPlace>> autocomplete(String input, {double? lat, double? lng}) async {
    if (input.trim().isEmpty) return [];
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'q': input,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'vn',
      'limit': '8',
      if (lat != null && lng != null) 'viewbox': '${lng - 0.5},${lat + 0.5},${lng + 0.5},${lat - 0.5}',
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      debugPrint('[places] search lỗi ${res.statusCode}: ${res.body}');
      return [];
    }
    final list = jsonDecode(res.body) as List;
    return list.cast<Map<String, dynamic>>().map(_fromNominatimJson).toList();
  }

  Future<ResolvedPlace?> reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse('$_base/reverse').replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'addressdetails': '1',
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      debugPrint('[places] reverse lỗi ${res.statusCode}: ${res.body}');
      return null;
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      debugPrint('[places] reverse lỗi: ${json['error']}');
      return null;
    }
    return _fromNominatimJson(json);
  }
}

/// Nominatim trả 'address' dạng key-value tự do (không có 'types' chuẩn hoá như Google) —
/// thử vài tên field hay gặp với địa chỉ Việt Nam cho từng cấp hành chính.
ResolvedPlace _fromNominatimJson(Map<String, dynamic> json) {
  final address = json['address'] as Map<String, dynamic>? ?? {};
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = address[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  final province = pick(['state', 'city', 'province']);
  final district = pick(['county', 'city_district', 'district']);
  final ward = pick(['suburb', 'quarter', 'neighbourhood', 'ward']);
  final houseNumber = pick(['house_number']);
  final road = pick(['road']);
  final line1 = [houseNumber, road].where((e) => e != null && e.isNotEmpty).join(' ');
  final displayName = json['display_name'] as String? ?? '';

  return ResolvedPlace(
    latitude: double.parse(json['lat'].toString()),
    longitude: double.parse(json['lon'].toString()),
    formattedAddress: displayName,
    line1: line1.isNotEmpty ? line1 : displayName,
    ward: ward,
    district: district,
    province: province,
  );
}
