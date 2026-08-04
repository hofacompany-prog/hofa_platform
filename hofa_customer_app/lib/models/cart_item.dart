import 'delivery_slot.dart';
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

  /// Giá gốc của biến thể lúc thêm vào giỏ (product_variants.price), không đổi kể cả khi
  /// [unitPrice] được cập nhật lại theo bậc giá — dùng để biết giá hiện tại có đang được
  /// giảm theo bậc hay không (unitPrice != basePrice) mà không cần hỏi lại server.
  final int basePrice;
  final int quantity;
  final String unit;
  final String? note;
  final List<ProductTopping> toppings;

  /// Các lần giao trong tuần (thứ + giờ) khách muốn nhận riêng cho món này khi đặt trước —
  /// 1 thứ có thể có nhiều giờ khác nhau nếu món này giao nhiều lần trong ngày.
  final List<DeliverySlot> deliverySlots;

  /// Chỉ có giá trị khi giỏ ở sales_model 'scheduled' — khách chọn lúc thêm vào giỏ:
  /// 'wholesale' (tab Giá sỉ) hay 'preorder' (tab Đặt trước). Món giao ngay thì null.
  final String? orderKind;

  CartItem({
    required this.lineId,
    required this.productId,
    required this.productName,
    this.productImage,
    required this.variantId,
    required this.variantName,
    required this.unitPrice,
    int? basePrice,
    required this.quantity,
    required this.unit,
    this.note,
    this.toppings = const [],
    this.deliverySlots = const [],
    this.orderKind,
  }) : basePrice = basePrice ?? unitPrice;

  int get toppingsTotal => toppings.fold(0, (sum, t) => sum + t.price);
  int get lineTotal => (unitPrice + toppingsTotal) * quantity;

  /// Cùng biến thể + cùng bộ topping + cùng orderKind thì gộp thành 1 dòng, khác thì
  /// tách dòng riêng (Giá sỉ và Đặt trước không được gộp chung dù cùng biến thể).
  String get lineKey =>
      '$variantId::${(toppings.map((t) => t.id).toList()..sort()).join(',')}::${orderKind ?? ''}';

  CartItem copyWith({
    int? quantity,
    int? unitPrice,
    List<ProductTopping>? toppings,
    List<DeliverySlot>? deliverySlots,
  }) => CartItem(
    lineId: lineId,
    productId: productId,
    productName: productName,
    productImage: productImage,
    variantId: variantId,
    variantName: variantName,
    unitPrice: unitPrice ?? this.unitPrice,
    basePrice: basePrice,
    quantity: quantity ?? this.quantity,
    unit: unit,
    note: note,
    toppings: toppings ?? this.toppings,
    deliverySlots: deliverySlots ?? this.deliverySlots,
    orderKind: orderKind,
  );

  Map<String, dynamic> toJson() => {
    'line_id': lineId,
    'product_id': productId,
    'product_name': productName,
    'product_image': productImage,
    'variant_id': variantId,
    'variant_name': variantName,
    'unit_price': unitPrice,
    'base_price': basePrice,
    'quantity': quantity,
    'unit': unit,
    'note': note,
    'toppings': toppings.map((t) => t.toJson()).toList(),
    'delivery_slots': deliverySlots.map((s) => s.toJson()).toList(),
    'order_kind': orderKind,
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
    basePrice:
        (json['base_price'] as num?)?.toInt() ??
        (json['unit_price'] as num?)?.toInt(),
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unit: json['unit'] as String? ?? 'cái',
    note: json['note'] as String?,
    toppings: (json['toppings'] as List? ?? [])
        .map((e) => ProductTopping.fromJson(e as Map<String, dynamic>))
        .toList(),
    deliverySlots: (json['delivery_slots'] as List? ?? [])
        .map((e) => DeliverySlot.fromJson(e as Map<String, dynamic>))
        .toList(),
    orderKind: json['order_kind'] as String?,
  );
}
