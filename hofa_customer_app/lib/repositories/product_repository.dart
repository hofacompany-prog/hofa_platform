import '../core/api_client.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/wholesale_tier.dart';

class ProductRepository {
  final _api = ApiClient.instance;

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> products({
    String? merchantId,
    String? q,
    String? salesModel,
    String? categoryId,
    bool? isFeatured,
    int limit = 50,
  }) async {
    final list = await _api.get('/products', query: {
      'limit': limit,
      if (merchantId != null) 'merchant_id': merchantId,
      if (q != null && q.isNotEmpty) 'q': q,
      if (salesModel != null) 'sales_model': salesModel,
      if (categoryId != null) 'category_id': categoryId,
      if (isFeatured != null) 'is_featured': isFeatured,
    }) as List;
    return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Product> product(String id) async => Product.fromJson(await _api.get('/products/$id') as Map<String, dynamic>);

  Future<List<WholesaleTier>> wholesaleTiers(String variantId) async {
    final list = await _api.get('/variants/$variantId/wholesale-tiers') as List;
    return list.map((e) => WholesaleTier.fromJson(e as Map<String, dynamic>)).toList();
  }
}
