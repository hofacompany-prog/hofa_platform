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
    toppings:
        (json['toppings'] as List?)
            ?.map((e) => OrderItemTopping.fromJson(e as Map<String, dynamic>))
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
  final String shipProvince;
  final int subtotal;
  final int deliveryFee;
  final int discountAmount;
  final int totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String? customerNote;
  final int? estimatedPrepMinutes;
  final int? lateMinutes;
  final int? defaultPrepMinutes;
  final DateTime? confirmSweepDeadline;
  final String salesModel;
  final DateTime? scheduledFor;
  final DateTime? preorderNotifiedAt;

  /// Đơn đầu tiên trong tuần mà đơn này gộp thanh toán chung (khách chọn "Thanh toán theo
  /// tuần" lúc đặt trước) — null nghĩa là đơn tự thanh toán riêng như bình thường. Chỉ là
  /// nhãn tham chiếu, KHÔNG tự đổi paymentStatus — vẫn phải tự xác nhận đã nhận tiền.
  final String? paymentGroupOrderId;
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
    required this.shipProvince,
    required this.subtotal,
    required this.deliveryFee,
    required this.discountAmount,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
    this.confirmedAt,
    this.customerNote,
    this.estimatedPrepMinutes,
    this.lateMinutes,
    this.defaultPrepMinutes,
    this.confirmSweepDeadline,
    this.salesModel = 'instant',
    this.scheduledFor,
    this.preorderNotifiedAt,
    this.paymentGroupOrderId,
    required this.items,
  });

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
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    confirmedAt: json['confirmed_at'] != null
        ? DateTime.tryParse(json['confirmed_at'].toString())
        : null,
    customerNote: json['customer_note'] as String?,
    estimatedPrepMinutes: (json['estimated_prep_minutes'] as num?)?.toInt(),
    lateMinutes: (json['late_minutes'] as num?)?.toInt(),
    defaultPrepMinutes: (json['default_prep_minutes'] as num?)?.toInt(),
    confirmSweepDeadline: json['confirm_sweep_deadline'] != null
        ? DateTime.tryParse(json['confirm_sweep_deadline'].toString())
        : null,
    salesModel: json['sales_model'] as String? ?? 'instant',
    scheduledFor: json['scheduled_for'] != null
        ? DateTime.tryParse(json['scheduled_for'].toString())
        : null,
    preorderNotifiedAt: json['preorder_notified_at'] != null
        ? DateTime.tryParse(json['preorder_notified_at'].toString())
        : null,
    paymentGroupOrderId: json['payment_group_order_id'] as String?,
    items:
        (json['items'] as List?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

/// Nhãn tiếng Việt + màu cho từng trạng thái — khớp enum order_status trong 01_schema.sql
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

/// Trạng thái tiếp theo cửa hàng được phép chuyển tới (khớp ORDER_STATUS_ROLES trong orders.js)
const nextMerchantStatus = {
  'placed': 'confirmed',
  'confirmed': 'preparing',
  'preparing': 'ready_for_pickup',
};
