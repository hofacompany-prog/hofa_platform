class ProductVariant {
  final String id;
  final String productId;
  final String name;
  final Map<String, dynamic> attributes;
  final int price;
  final int? comparePrice;
  final int? wholesalePrice;
  final int? weightGram;
  final bool isDefault;
  final bool isActive;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.attributes,
    required this.price,
    this.comparePrice,
    this.wholesalePrice,
    this.weightGram,
    required this.isDefault,
    required this.isActive,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        id: json['id'] as String,
        productId: json['product_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        attributes: (json['attributes'] as Map?)?.cast<String, dynamic>() ?? {},
        price: (json['price'] as num?)?.toInt() ?? 0,
        comparePrice: (json['compare_price'] as num?)?.toInt(),
        wholesalePrice: (json['wholesale_price'] as num?)?.toInt(),
        weightGram: (json['weight_gram'] as num?)?.toInt(),
        isDefault: json['is_default'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );
}
