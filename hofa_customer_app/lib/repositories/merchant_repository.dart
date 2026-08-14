import '../core/api_client.dart';
import '../models/merchant.dart';
import '../models/merchant_classification.dart';
import '../models/merchant_fee_tier.dart';
import '../models/branch.dart';

class MerchantRepository {
  final _api = ApiClient.instance;

  Future<List<Merchant>> merchants({
    String? q,
    String? merchantType,
    int limit = 50,
    int offset = 0,
    double? lat,
    double? lng,
    // 'distance' = sắp xếp "Gần tôi" (chỉ có tác dụng khi có lat/lng), null/khác = mặc định
    // (đánh giá cao trước, xem GET /merchants).
    String? sort,
    // Lọc theo phân loại cửa hàng (Nhà hàng/Cà phê/...) — khớp NẾU CÓ ÍT NHẤT 1 phân loại
    // trùng, xem hofa-db/71_merchant_classifications.sql.
    Set<String>? classificationIds,
  }) async {
    final list =
        await _api.get(
              '/merchants',
              query: {
                'limit': limit,
                'offset': offset,
                if (q != null && q.isNotEmpty) 'q': q,
                if (merchantType != null) 'merchant_type': merchantType,
                if (lat != null && lng != null) 'lat': lat,
                if (lat != null && lng != null) 'lng': lng,
                if (sort != null) 'sort': sort,
                if (classificationIds != null && classificationIds.isNotEmpty)
                  'classification_ids': classificationIds.join(','),
              },
            )
            as List;
    return list
        .map((e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Danh sách phân loại cửa hàng — viên nang lọc ở trang chủ.
  Future<List<MerchantClassification>> merchantClassifications() async {
    final list = await _api.get('/merchant-classifications') as List;
    return list
        .map((e) => MerchantClassification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Merchant> merchant(String id, {double? lat, double? lng}) async =>
      Merchant.fromJson(
        await _api.get(
              '/merchants/$id',
              query: {
                if (lat != null && lng != null) 'lat': lat,
                if (lat != null && lng != null) 'lng': lng,
              },
            )
            as Map<String, dynamic>,
      );

  Future<List<Branch>> branches(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/branches') as List;
    return list.map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Branch> branch(String id) async =>
      Branch.fromJson(await _api.get('/branches/$id') as Map<String, dynamic>);

  Future<List<MerchantFeeTier>> feeTiers(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/fee-tiers') as List;
    return list
        .map((e) => MerchantFeeTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
