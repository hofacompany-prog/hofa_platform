class Topping {
  final String id;
  final String groupId;
  final String name;
  final int price;
  final int sortOrder;
  final bool isActive;

  Topping({
    required this.id,
    required this.groupId,
    required this.name,
    required this.price,
    required this.sortOrder,
    this.isActive = true,
  });

  factory Topping.fromJson(Map<String, dynamic> json) => Topping(
    id: json['id'] as String,
    groupId: json['group_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    isActive: json['is_active'] as bool? ?? true,
  );
}

/// Nhóm topping là thư viện dùng chung của 1 cửa hàng (merchantId), gắn được vào nhiều
/// sản phẩm — xem hofa_store_app/lib/models/product.dart (bản gốc, cùng cấu trúc JSON).
class ToppingGroup {
  final String id;
  final String merchantId;
  final String name;
  final bool isRequired;
  final bool allowMultiple;
  final int sortOrder;
  final int linkedProductCount;
  final List<Topping> toppings;

  ToppingGroup({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.isRequired,
    required this.allowMultiple,
    required this.sortOrder,
    this.linkedProductCount = 0,
    required this.toppings,
  });

  factory ToppingGroup.fromJson(Map<String, dynamic> json) => ToppingGroup(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isRequired: json['is_required'] as bool? ?? false,
    allowMultiple: json['allow_multiple'] as bool? ?? false,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    linkedProductCount: (json['linked_product_count'] as num?)?.toInt() ?? 0,
    toppings:
        (json['toppings'] as List?)
            ?.map((e) => Topping.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
