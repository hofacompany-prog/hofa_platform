class ProductVariant {
  final String id;
  final String name;
  final int price;
  final bool isDefault;

  ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    required this.isDefault,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) =>
      ProductVariant(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toInt() ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
      );
}

class Product {
  final String id;
  final String name;
  final List<ProductVariant> variants;

  Product({required this.id, required this.name, required this.variants});

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    variants:
        (json['variants'] as List?)
            ?.map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
