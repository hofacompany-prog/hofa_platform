class OrderItem {
  final String id;
  final String productName;
  final String? variantName;
  final String? unit;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final String? note;

  OrderItem({
    required this.id,
    required this.productName,
    this.variantName,
    this.unit,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.note,
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
  final int subtotal;
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
    required this.subtotal,
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
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
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
}
