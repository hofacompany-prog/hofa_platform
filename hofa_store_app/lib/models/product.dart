class ProductVariant {
  final String id;
  final String productId;
  final String? sku;
  final String name;
  final int price;
  final int? comparePrice;
  final int? costPrice;
  final int? wholesalePrice;
  final bool isDefault;
  final bool isActive;

  ProductVariant({
    required this.id,
    required this.productId,
    this.sku,
    required this.name,
    required this.price,
    this.comparePrice,
    this.costPrice,
    this.wholesalePrice,
    required this.isDefault,
    required this.isActive,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
    id: json['id'] as String,
    productId: json['product_id'] as String? ?? '',
    sku: json['sku'] as String?,
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    comparePrice: (json['compare_price'] as num?)?.toInt(),
    costPrice: (json['cost_price'] as num?)?.toInt(),
    wholesalePrice: (json['wholesale_price'] as num?)?.toInt(),
    isDefault: json['is_default'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class Topping {
  final String id;
  final String groupId;
  final String name;
  final int price;
  final int sortOrder;

  Topping({
    required this.id,
    required this.groupId,
    required this.name,
    required this.price,
    required this.sortOrder,
  });

  factory Topping.fromJson(Map<String, dynamic> json) => Topping(
    id: json['id'] as String,
    groupId: json['group_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class ToppingGroup {
  final String id;
  final String productId;
  final String name;
  final bool isRequired;
  final bool allowMultiple;
  final int sortOrder;
  final List<Topping> toppings;

  ToppingGroup({
    required this.id,
    required this.productId,
    required this.name,
    required this.isRequired,
    required this.allowMultiple,
    required this.sortOrder,
    required this.toppings,
  });

  factory ToppingGroup.fromJson(Map<String, dynamic> json) => ToppingGroup(
    id: json['id'] as String,
    productId: json['product_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isRequired: json['is_required'] as bool? ?? false,
    allowMultiple: json['allow_multiple'] as bool? ?? false,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    toppings:
        (json['toppings'] as List?)
            ?.map((e) => Topping.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class Product {
  final String id;
  final String merchantId;
  final String name;
  final String? description;
  final String salesModel;
  final String status;
  final String unit;
  final List<String> images;
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.merchantId,
    required this.name,
    this.description,
    required this.salesModel,
    required this.status,
    required this.unit,
    required this.images,
    required this.variants,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    salesModel: json['sales_model'] as String? ?? 'instant',
    status: json['status'] as String? ?? 'draft',
    unit: json['unit'] as String? ?? 'cái',
    images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
    variants:
        (json['variants'] as List?)
            ?.map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );

  int get lowestPrice => variants.isEmpty
      ? 0
      : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
}
