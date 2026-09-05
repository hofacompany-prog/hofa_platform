class OrderItemTopping {
  final String name;
  final int price;

  OrderItemTopping({required this.name, required this.price});

  factory OrderItemTopping.fromJson(Map<String, dynamic> json) =>
      OrderItemTopping(
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toInt() ?? 0,
      );
}

class OrderItem {
  final String id;
  final String productName;
  final String? variantName;
  final String? unit;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final String? note;
  final List<OrderItemTopping> toppings;

  OrderItem({
    required this.id,
    required this.productName,
    this.variantName,
    this.unit,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.note,
    this.toppings = const [],
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as String,
    productName: json['product_name'] as String? ?? '',
    variantName: json['variant_name'] as String?,
    unit: json['unit'] as String?,
    unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    lineTotal: (json['line_total'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
    toppings:
        (json['toppings'] as List?)
            ?.map((t) => OrderItemTopping.fromJson(t as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

class Order {
  final String id;
  final String orderCode;
  final String merchantId;
  final String branchId;
  final String status;
  final String shipRecipientName;
  final String shipRecipientPhone;
  final String shipLine1;
  final String? shipWard;
  final String? shipDistrict;
  final String shipProvince;
  final double? shipLatitude;
  final double? shipLongitude;
  final String? shipNote;
  final String? customerNote;
  final int subtotal;
  // Đơn mua hộ: đã CỘNG THẲNG vào giá món trong subtotal — trừ ngược ra để biết đúng tiền hàng
  // THẬT tài xế cần ứng tại quán (xem _BuyOnBehalfShoppingCard,
  // hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql).
  final int buyOnBehalfFee;
  final int totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime? deliveredAt;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.orderCode,
    required this.merchantId,
    required this.branchId,
    required this.status,
    required this.shipRecipientName,
    required this.shipRecipientPhone,
    required this.shipLine1,
    this.shipWard,
    this.shipDistrict,
    required this.shipProvince,
    this.shipLatitude,
    this.shipLongitude,
    this.shipNote,
    this.customerNote,
    required this.subtotal,
    this.buyOnBehalfFee = 0,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.deliveredAt,
    this.items = const [],
  });

  String get shipFullAddress => [
    shipLine1,
    shipWard,
    shipDistrict,
    shipProvince,
  ].where((e) => e != null && e.isNotEmpty).join(', ');

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    orderCode: json['order_code'] as String? ?? '',
    merchantId: json['merchant_id'] as String,
    branchId: json['branch_id'] as String,
    status: json['status'] as String? ?? '',
    shipRecipientName: json['ship_recipient_name'] as String? ?? '',
    shipRecipientPhone: json['ship_recipient_phone'] as String? ?? '',
    shipLine1: json['ship_line1'] as String? ?? '',
    shipWard: json['ship_ward'] as String?,
    shipDistrict: json['ship_district'] as String?,
    shipProvince: json['ship_province'] as String? ?? '',
    shipLatitude: json['ship_latitude'] != null
        ? double.tryParse('${json['ship_latitude']}')
        : null,
    shipLongitude: json['ship_longitude'] != null
        ? double.tryParse('${json['ship_longitude']}')
        : null,
    shipNote: json['ship_note'] as String?,
    customerNote: json['customer_note'] as String?,
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
    buyOnBehalfFee: (json['buy_on_behalf_fee'] as num?)?.toInt() ?? 0,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    paymentMethod: json['payment_method'] as String? ?? 'cod',
    paymentStatus: json['payment_status'] as String? ?? 'pending',
    deliveredAt: json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'].toString())
        : null,
    items: json['items'] is List
        ? (json['items'] as List)
              .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList()
        : const [],
  );

  /// Tổng SỐ LƯỢNG món (cộng dồn quantity từng dòng) — khác items.length (chỉ đếm số DÒNG sản
  /// phẩm khác nhau, đơn "2x Cá basa" chỉ có 1 dòng nhưng phải hiện 2 món).
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);
}
