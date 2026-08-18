import '../core/api_client.dart';
import '../models/product.dart';

class ProductRepository {
  final _api = ApiClient.instance;

  Future<List<Product>> products({required String merchantId}) async {
    final list =
        await _api.get(
              '/products',
              query: {'merchant_id': merchantId, 'limit': 200},
            )
            as List;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Báo giá sai của 1 biến thể sản phẩm — admin duyệt qua GET/PATCH /admin/price-reports
  /// (web admin), xem hofa-db/89_product_price_reports.sql.
  Future<void> reportPrice({
    required String variantId,
    required int reportedPrice,
  }) async {
    await _api.post(
      '/price-reports',
      body: {'variant_id': variantId, 'reported_price': reportedPrice},
    );
  }
}
