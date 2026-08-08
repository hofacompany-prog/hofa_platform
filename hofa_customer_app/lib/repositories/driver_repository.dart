import '../core/api_client.dart';
import '../models/available_driver.dart';

class DriverRepository {
  final _api = ApiClient.instance;

  /// Tài xế đang online gần [lat]/[lng] nhất, dùng cho khách chọn tài xế ở đơn mua hộ.
  /// [excludeIds] loại bớt tài xế đã từ chối đơn này (lúc chọn lại).
  Future<List<AvailableDriver>> available({
    required double lat,
    required double lng,
    List<String> excludeIds = const [],
  }) async {
    final list = await _api.get('/drivers/available', query: {
      'latitude': lat,
      'longitude': lng,
      if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
    }) as List;
    return list.map((e) => AvailableDriver.fromJson(e as Map<String, dynamic>)).toList();
  }
}
