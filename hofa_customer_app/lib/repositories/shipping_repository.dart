import '../core/api_client.dart';
import '../models/shipping_fee_settings.dart';

class ShippingRepository {
  final _api = ApiClient.instance;

  Future<ShippingFeeSettings?> feeSettings() async {
    final json =
        await _api.get('/shipping-fee-settings') as Map<String, dynamic>?;
    return json == null ? null : ShippingFeeSettings.fromJson(json);
  }

  /// Khoảng cách ĐƯỜNG ĐI THỰC TẾ (km) giữa 2 toạ độ, qua GET /route-distance (server gọi OSRM,
  /// tự rớt về đường chim bay nếu OSRM lỗi — xem server/src/routing.js). Dùng để ước tính phí
  /// ship lúc checkout thay cho core/geo.dart#haversineKm (chỉ còn dùng làm fallback tức thời
  /// trong lúc chờ kết quả này tải xong, xem checkout_screen.dart).
  Future<double> routeDistanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) async {
    final json =
        await _api.get(
              '/route-distance',
              query: {'lat1': lat1, 'lng1': lng1, 'lat2': lat2, 'lng2': lng2},
            )
            as Map<String, dynamic>;
    return (json['distance_km'] as num).toDouble();
  }
}
