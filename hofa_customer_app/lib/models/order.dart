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
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final String? note;
  final List<OrderItemTopping> toppings;

  OrderItem({
    required this.id,
    required this.productName,
    this.variantName,
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
    unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    lineTotal: (json['line_total'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
    toppings: (json['toppings'] as List? ?? [])
        .map((e) => OrderItemTopping.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class OrderStatusEvent {
  final String status;
  final String? note;
  final DateTime createdAt;

  OrderStatusEvent({required this.status, this.note, required this.createdAt});

  factory OrderStatusEvent.fromJson(Map<String, dynamic> json) =>
      OrderStatusEvent(
        status:
            json['status'] as String? ?? json['new_status'] as String? ?? '',
        note: json['note'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
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
  final String shipProvince;
  final int subtotal;
  final int deliveryFee;
  final int discountAmount;
  final int totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime? scheduledFor;
  final String? customerNote;
  final DateTime createdAt;
  final List<OrderItem> items;
  final String? merchantName;

  Order({
    required this.id,
    required this.orderCode,
    required this.merchantId,
    required this.branchId,
    required this.status,
    required this.shipRecipientName,
    required this.shipRecipientPhone,
    required this.shipLine1,
    required this.shipProvince,
    required this.subtotal,
    required this.deliveryFee,
    required this.discountAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.scheduledFor,
    this.customerNote,
    required this.createdAt,
    required this.items,
    this.merchantName,
  });

  bool get canCancel =>
      ['pending_payment', 'placed', 'confirmed'].contains(status);
  bool get canReview => ['delivered', 'completed'].contains(status);

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    orderCode: json['order_code'] as String? ?? '',
    merchantId: json['merchant_id'] as String,
    branchId: json['branch_id'] as String,
    status: json['status'] as String,
    shipRecipientName: json['ship_recipient_name'] as String? ?? '',
    shipRecipientPhone: json['ship_recipient_phone'] as String? ?? '',
    shipLine1: json['ship_line1'] as String? ?? '',
    shipProvince: json['ship_province'] as String? ?? '',
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
    deliveryFee: (json['delivery_fee'] as num?)?.toInt() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    paymentMethod: json['payment_method'] as String? ?? 'cod',
    paymentStatus: json['payment_status'] as String? ?? 'pending',
    scheduledFor: json['scheduled_for'] != null
        ? DateTime.tryParse(json['scheduled_for'] as String)
        : null,
    customerNote: json['customer_note'] as String?,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    items:
        (json['items'] as List?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    merchantName: json['merchant_name'] as String?,
  );
}

/// Nhãn tiếng Việt cho từng trạng thái — khớp enum order_status trong 01_schema.sql
const orderStatusLabels = {
  'pending_payment': 'Chờ thanh toán',
  'placed': 'Đơn mới',
  'confirmed': 'Đã xác nhận',
  'preparing': 'Đang chuẩn bị',
  'ready_for_pickup': 'Chờ tài xế lấy',
  'assigned': 'Đã gán tài xế',
  'picked_up': 'Đã lấy hàng',
  'delivering': 'Đang giao',
  'delivered': 'Đã giao',
  'completed': 'Hoàn tất',
  'cancelled': 'Đã huỷ',
  'refunded': 'Đã hoàn tiền',
};
