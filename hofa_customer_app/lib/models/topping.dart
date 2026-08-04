class ProductTopping {
  final String id;
  final String name;
  final int price;

  ProductTopping({required this.id, required this.name, required this.price});

  factory ProductTopping.fromJson(Map<String, dynamic> json) => ProductTopping(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
}

class ToppingGroup {
  final String id;
  final String name;
  final bool isRequired;
  final bool allowMultiple;
  final List<ProductTopping> toppings;

  ToppingGroup({
    required this.id,
    required this.name,
    required this.isRequired,
    required this.allowMultiple,
    required this.toppings,
  });

  factory ToppingGroup.fromJson(Map<String, dynamic> json) => ToppingGroup(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    isRequired: json['is_required'] as bool? ?? false,
    allowMultiple: json['allow_multiple'] as bool? ?? false,
    toppings: (json['toppings'] as List? ?? [])
        .map((e) => ProductTopping.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
