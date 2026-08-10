import '../core/api_client.dart';
import '../models/product.dart';
import '../models/category.dart';

Map<String, dynamic> _tierPayload(WholesaleTier t) => {
  'min_quantity': t.minQuantity,
  if (t.maxQuantity != null) 'max_quantity': t.maxQuantity,
  'unit_price': t.unitPrice,
  'min_days_per_week': t.minDaysPerWeek,
  if (t.unitPriceDays != null) 'unit_price_days': t.unitPriceDays,
  if (t.unitPriceBoth != null) 'unit_price_both': t.unitPriceBoth,
  if (t.minOrderQuantity != null) 'min_order_quantity': t.minOrderQuantity,
};

class ProductRepository {
  final _api = ApiClient.instance;

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MerchantCategory>> merchantCategories({
    required String merchantId,
    String? categoryId,
  }) async {
    final list =
        await _api.get(
              '/merchant-categories',
              query: {
                'merchant_id': merchantId,
                if (categoryId != null) 'category_id': categoryId,
              },
            )
            as List;
    return list
        .map((e) => MerchantCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MerchantCategory> createMerchantCategory({
    required String merchantId,
    required String categoryId,
    required String name,
  }) async => MerchantCategory.fromJson(
    await _api.post(
          '/merchant-categories',
          body: {
            'merchant_id': merchantId,
            'category_id': categoryId,
            'name': name,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateMerchantCategory(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _api.patch('/merchant-categories/$id', body: data);
  }

  Future<void> deleteMerchantCategory(String id) async {
    await _api.delete('/merchant-categories/$id');
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
    String? merchantCategoryId,
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
    List<String> toppingGroupIds = const [],
    List<WholesaleTier> wholesaleTiers = const [],
    List<ProductVariant> extraVariants = const [],
    Map<String, List<WholesaleTier>> tiersByVariant = const {},
  }) async => Product.fromJson(
    await _api.post(
          '/products',
          body: {
            'merchant_id': merchantId,
            if (merchantCategoryId != null)
              'merchant_category_id': merchantCategoryId,
            'name': name,
            if (description != null && description.isNotEmpty)
              'description': description,
            'unit': unit,
            'sales_model': salesModel,
            'status': status,
            'images': [imageUrl],
            if (toppingGroupIds.isNotEmpty)
              'topping_group_ids': toppingGroupIds,
            'variants': [
              {
                'name': unit,
                'price': price,
                if (comparePrice != null) 'compare_price': comparePrice,
                if (costPrice != null) 'cost_price': costPrice,
                if (wholesalePrice != null) 'wholesale_price': wholesalePrice,
                'is_default': true,
                if (wholesaleTiers.isNotEmpty)
                  'wholesale_tiers': wholesaleTiers.map(_tierPayload).toList(),
              },
              for (final v in extraVariants)
                {
                  'name': v.name,
                  if (v.sku != null && v.sku!.isNotEmpty) 'sku': v.sku,
                  'price': v.price,
                  if (v.comparePrice != null) 'compare_price': v.comparePrice,
                  if (v.costPrice != null) 'cost_price': v.costPrice,
                  if (v.wholesalePrice != null)
                    'wholesale_price': v.wholesalePrice,
                  'is_default': false,
                  if ((tiersByVariant[v.id] ?? []).isNotEmpty)
                    'wholesale_tiers': tiersByVariant[v.id]!
                        .map(_tierPayload)
                        .toList(),
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

  Future<List<WholesaleTier>> wholesaleTiers(String variantId) async {
    final list = await _api.get('/variants/$variantId/wholesale-tiers') as List;
    return list
        .map((e) => WholesaleTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WholesaleTier> createWholesaleTier({
    required String variantId,
    required int minQuantity,
    int? maxQuantity,
    required int unitPrice,
    int minDaysPerWeek = 0,
    int? unitPriceDays,
    int? unitPriceBoth,
    int? minOrderQuantity,
  }) async => WholesaleTier.fromJson(
    await _api.post(
          '/variants/$variantId/wholesale-tiers',
          body: {
            'min_quantity': minQuantity,
            if (maxQuantity != null) 'max_quantity': maxQuantity,
            'unit_price': unitPrice,
            'min_days_per_week': minDaysPerWeek,
            if (unitPriceDays != null) 'unit_price_days': unitPriceDays,
            if (unitPriceBoth != null) 'unit_price_both': unitPriceBoth,
            if (minOrderQuantity != null)
              'min_order_quantity': minOrderQuantity,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateWholesaleTier(String id, Map<String, dynamic> data) async {
    await _api.patch('/wholesale-tiers/$id', body: data);
  }

  Future<void> deleteWholesaleTier(String id) async {
    await _api.delete('/wholesale-tiers/$id');
  }

  /// Nhóm topping đang gắn vào 1 sản phẩm.
  Future<List<ToppingGroup>> toppingGroups(String productId) async {
    final list = await _api.get('/products/$productId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Đặt lại toàn bộ danh sách nhóm topping gắn vào 1 sản phẩm (thay thế, không cộng dồn).
  Future<void> setProductToppingGroups(
    String productId,
    List<String> groupIds,
  ) async {
    await _api.put(
      '/products/$productId/topping-groups',
      body: {'group_ids': groupIds},
    );
  }

  /// Toàn bộ nhóm topping (thư viện dùng chung) của 1 cửa hàng, kèm số sản phẩm đang gắn.
  Future<List<ToppingGroup>> merchantToppingGroups(String merchantId) async {
    final list =
        await _api.get('/merchants/$merchantId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ToppingGroup> toppingGroup(String id) async => ToppingGroup.fromJson(
    await _api.get('/topping-groups/$id') as Map<String, dynamic>,
  );

  Future<ToppingGroup> createToppingGroup({
    required String merchantId,
    required String name,
    required bool isRequired,
    required bool allowMultiple,
  }) async => ToppingGroup.fromJson(
    await _api.post(
          '/merchants/$merchantId/topping-groups',
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
