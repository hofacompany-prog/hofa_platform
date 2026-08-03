import '../core/api_client.dart';
import '../models/product.dart';
import '../models/category.dart';

class ProductRepository {
  final _api = ApiClient.instance;

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> list(String merchantId) async {
    final list =
        await _api.get(
              '/products',
              query: {'merchant_id': merchantId, 'limit': 100},
            )
            as List;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Product> get(String id) async =>
      Product.fromJson(await _api.get('/products/$id') as Map<String, dynamic>);

  Future<Product> create({
    required String merchantId,
    required String name,
    String? description,
    required String unit,
    required String salesModel,
    required String status,
    required String imageUrl,
    required int price,
    int? comparePrice,
    int? costPrice,
    int? wholesalePrice,
  }) async => Product.fromJson(
    await _api.post(
          '/products',
          body: {
            'merchant_id': merchantId,
            'name': name,
            if (description != null && description.isNotEmpty)
              'description': description,
            'unit': unit,
            'sales_model': salesModel,
            'status': status,
            'images': [imageUrl],
            'variants': [
              {
                'name': unit,
                'price': price,
                if (comparePrice != null) 'compare_price': comparePrice,
                if (costPrice != null) 'cost_price': costPrice,
                if (wholesalePrice != null) 'wholesale_price': wholesalePrice,
                'is_default': true,
              },
            ],
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> update(String id, Map<String, dynamic> data) async {
    await _api.patch('/products/$id', body: data);
  }

  Future<void> delete(String id) async {
    await _api.delete('/products/$id');
  }

  Future<ProductVariant> createVariant({
    required String productId,
    required String name,
    String? sku,
    required int price,
    int? comparePrice,
    int? costPrice,
    int? wholesalePrice,
    bool isDefault = false,
  }) async => ProductVariant.fromJson(
    await _api.post(
          '/products/$productId/variants',
          body: {
            'name': name,
            if (sku != null && sku.isNotEmpty) 'sku': sku,
            'price': price,
            if (comparePrice != null) 'compare_price': comparePrice,
            if (costPrice != null) 'cost_price': costPrice,
            if (wholesalePrice != null) 'wholesale_price': wholesalePrice,
            'is_default': isDefault,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateVariant(String id, Map<String, dynamic> data) async {
    await _api.patch('/variants/$id', body: data);
  }

  Future<void> deleteVariant(String id) async {
    await _api.delete('/variants/$id');
  }

  Future<List<ToppingGroup>> toppingGroups(String productId) async {
    final list = await _api.get('/products/$productId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ToppingGroup> createToppingGroup({
    required String productId,
    required String name,
    required bool isRequired,
    required bool allowMultiple,
  }) async => ToppingGroup.fromJson(
    await _api.post(
          '/products/$productId/topping-groups',
          body: {
            'name': name,
            'is_required': isRequired,
            'allow_multiple': allowMultiple,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateToppingGroup(String id, Map<String, dynamic> data) async {
    await _api.patch('/topping-groups/$id', body: data);
  }

  Future<void> deleteToppingGroup(String id) async {
    await _api.delete('/topping-groups/$id');
  }

  Future<Topping> createTopping({
    required String groupId,
    required String name,
    required int price,
  }) async => Topping.fromJson(
    await _api.post(
          '/topping-groups/$groupId/toppings',
          body: {'name': name, 'price': price},
        )
        as Map<String, dynamic>,
  );

  Future<void> updateTopping(String id, Map<String, dynamic> data) async {
    await _api.patch('/toppings/$id', body: data);
  }

  Future<void> deleteTopping(String id) async {
    await _api.delete('/toppings/$id');
  }
}
