/// Món trong giỏ — chỉ tồn tại phía client (chưa phải đơn hàng thật) nên không có fromJson
/// từ API; toJson() dùng để đóng gói qua shared_preferences (lưu tạm) và khi gửi POST /orders.
class CartItem {
  final String productId;
  final String productName;
  final String? productImage;
  final String variantId;
  final String variantName;
  final int unitPrice;
  final int quantity;
  final String unit;
  final String? note;

  CartItem({
    required this.productId,
    required this.productName,
    this.productImage,
    required this.variantId,
    required this.variantName,
    required this.unitPrice,
    required this.quantity,
    required this.unit,
    this.note,
  });

  int get lineTotal => unitPrice * quantity;

  CartItem copyWith({int? quantity}) => CartItem(
        productId: productId,
        productName: productName,
        productImage: productImage,
        variantId: variantId,
        variantName: variantName,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        unit: unit,
        note: note,
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'product_image': productImage,
        'variant_id': variantId,
        'variant_name': variantName,
        'unit_price': unitPrice,
        'quantity': quantity,
        'unit': unit,
        'note': note,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['product_id'] as String,
        productName: json['product_name'] as String? ?? '',
        productImage: json['product_image'] as String?,
        variantId: json['variant_id'] as String,
        variantName: json['variant_name'] as String? ?? '',
        unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unit: json['unit'] as String? ?? 'cái',
        note: json['note'] as String?,
      );
}
