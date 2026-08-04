import 'topping.dart';

/// Món trong giỏ — chỉ tồn tại phía client (chưa phải đơn hàng thật) nên không có fromJson
/// từ API; toJson() dùng để đóng gói qua shared_preferences (lưu tạm) và khi gửi POST /orders.
class CartItem {
  /// Định danh riêng cho từng dòng trong giỏ (không phải variantId) — 1 biến thể có thể xuất
  /// hiện nhiều dòng nếu chọn topping khác nhau, nên không thể dùng variantId để +/- số lượng
  /// hay xoá được nữa.
  final String lineId;
  final String productId;
  final String productName;
  final String? productImage;
  final String variantId;
  final String variantName;
  final int unitPrice;
  final int quantity;
  final String unit;
  final String? note;
  final List<ProductTopping> toppings;

  /// Các ngày trong tuần (1=T2..7=CN) khách muốn nhận riêng cho món này khi đặt trước.
  final List<int> weekdays;

  CartItem({
    required this.lineId,
    required this.productId,
    required this.productName,
    this.productImage,
    required this.variantId,
    required this.variantName,
    required this.unitPrice,
    required this.quantity,
    required this.unit,
    this.note,
    this.toppings = const [],
    this.weekdays = const [],
  });

  int get toppingsTotal => toppings.fold(0, (sum, t) => sum + t.price);
  int get lineTotal => (unitPrice + toppingsTotal) * quantity;

  /// Cùng biến thể + cùng bộ topping thì gộp thành 1 dòng, khác thì tách dòng riêng.
  String get lineKey =>
      '$variantId::${(toppings.map((t) => t.id).toList()..sort()).join(',')}';

  CartItem copyWith({
    int? quantity,
    List<ProductTopping>? toppings,
    List<int>? weekdays,
  }) => CartItem(
    lineId: lineId,
    productId: productId,
    productName: productName,
    productImage: productImage,
    variantId: variantId,
    variantName: variantName,
    unitPrice: unitPrice,
    quantity: quantity ?? this.quantity,
    unit: unit,
    note: note,
    toppings: toppings ?? this.toppings,
    weekdays: weekdays ?? this.weekdays,
  );

  Map<String, dynamic> toJson() => {
    'line_id': lineId,
    'product_id': productId,
    'product_name': productName,
    'product_image': productImage,
    'variant_id': variantId,
    'variant_name': variantName,
    'unit_price': unitPrice,
    'quantity': quantity,
    'unit': unit,
    'note': note,
    'toppings': toppings.map((t) => t.toJson()).toList(),
    'weekdays': weekdays,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    lineId:
        json['line_id'] as String? ??
        '${json['variant_id']}_${DateTime.now().microsecondsSinceEpoch}',
    productId: json['product_id'] as String,
    productName: json['product_name'] as String? ?? '',
    productImage: json['product_image'] as String?,
    variantId: json['variant_id'] as String,
    variantName: json['variant_name'] as String? ?? '',
    unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unit: json['unit'] as String? ?? 'cái',
    note: json['note'] as String?,
    toppings: (json['toppings'] as List? ?? [])
        .map((e) => ProductTopping.fromJson(e as Map<String, dynamic>))
        .toList(),
    weekdays: (json['weekdays'] as List? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
  );
}
