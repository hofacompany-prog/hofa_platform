import '../core/api_client.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/topping.dart';
import '../models/wholesale_tier.dart';

class ProductRepository {
  final _api = ApiClient.instance;

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MerchantCategory>> merchantCategories(String merchantId) async {
    final list =
        await _api.get(
              '/merchant-categories',
              query: {'merchant_id': merchantId},
            )
            as List;
    return list
        .map((e) => MerchantCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> products({
    String? merchantId,
    String? q,
    String? salesModel,
    String? categoryId,
    bool? isFeatured,
    int limit = 50,
    int offset = 0,
  }) async {
    final list =
        await _api.get(
              '/products',
              query: {
                'limit': limit,
                'offset': offset,
                if (merchantId != null) 'merchant_id': merchantId,
                if (q != null && q.isNotEmpty) 'q': q,
                if (salesModel != null) 'sales_model': salesModel,
                if (categoryId != null) 'category_id': categoryId,
                if (isFeatured != null) 'is_featured': isFeatured,
              },
            )
            as List;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Product> product(String id) async =>
      Product.fromJson(await _api.get('/products/$id') as Map<String, dynamic>);

  Future<List<WholesaleTier>> wholesaleTiers(String variantId) async {
    final list = await _api.get('/variants/$variantId/wholesale-tiers') as List;
    return list
        .map((e) => WholesaleTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ToppingGroup>> toppingGroups(String productId) async {
    final list = await _api.get('/products/$productId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
