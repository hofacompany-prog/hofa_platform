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
  final String? productId;
  final String productName;
  final String? variantName;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final String? note;
  final List<OrderItemTopping> toppings;

  OrderItem({
    required this.id,
    this.productId,
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
    productId: json['product_id'] as String?,
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

  factory OrderStatusEvent.fromJson(
    Map<String, dynamic> json,
  ) => OrderStatusEvent(
    // Cột thật trong order_status_history là to_status — status/new_status chỉ giữ lại
    // để tương thích ngược nếu API từng trả tên khác trước đây.
    status:
        json['to_status'] as String? ??
        json['status'] as String? ??
        json['new_status'] as String? ??
        '',
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
  final String salesModel;
  final String shipRecipientName;
  final String shipRecipientPhone;
  final String shipLine1;
  final String shipProvince;
  final int subtotal;
  final int deliveryFee;
  final int discountAmount;
  final int buyOnBehalfFee;
  final int totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime? scheduledFor;
  final String? customerNote;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final List<OrderItem> items;
  final String? merchantName;
  final String? merchantType;
  final String? selectedDriverId;

  Order({
    required this.id,
    required this.orderCode,
    required this.merchantId,
    required this.branchId,
    required this.status,
    required this.salesModel,
    required this.shipRecipientName,
    required this.shipRecipientPhone,
    required this.shipLine1,
    required this.shipProvince,
    required this.subtotal,
    required this.deliveryFee,
    required this.discountAmount,
    this.buyOnBehalfFee = 0,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.scheduledFor,
    this.customerNote,
    required this.createdAt,
    this.deliveredAt,
    required this.items,
    this.merchantName,
    this.merchantType,
    this.selectedDriverId,
  });

  /// Đơn "đặt trước"/"giá sỉ" (salesModel 'scheduled', khác 'instant' giao ngay) khách chỉ tự
  /// huỷ được TRƯỚC khi cửa hàng xác nhận (pending_payment/placed) — cửa hàng xác nhận sớm ngay
  /// từ lúc đặt (xem hofa-db/60_preorder_manual_confirm.sql) đồng nghĩa đã bắt đầu giữ
  /// chỗ/chuẩn bị nguyên liệu theo lịch, nên từ 'confirmed' trở đi chỉ cửa hàng mới được huỷ
  /// (xem canContactMerchantToCancel bên dưới cho lối thay thế phía khách). Đơn giao ngay
  /// (instant) giữ nguyên như cũ, huỷ được tới hết 'confirmed'.
  bool get canCancel => salesModel == 'scheduled'
      ? ['pending_payment', 'placed'].contains(status)
      : ['pending_payment', 'placed', 'confirmed'].contains(status);

  /// Đơn "đặt trước"/"giá sỉ" đã qua giai đoạn tự huỷ được (cửa hàng đã xác nhận, đang giữ
  /// chỗ/chuẩn bị) nhưng chưa bàn giao cho tài xế — khách không tự huỷ được nhưng vẫn cần 1 lối
  /// liên hệ cửa hàng để nhờ huỷ hộ.
  bool get canContactMerchantToCancel =>
      salesModel == 'scheduled' && ['confirmed', 'preparing'].contains(status);

  /// Đủ điều kiện đánh giá — đơn đã giao VÀ còn trong 3 ngày kể từ lúc giao, quá hạn thì
  /// ẩn hẳn phần đánh giá (khớp yêu cầu "sẽ bị ẩn sau 3 ngày và không đánh giá được nữa").
  bool get canReview =>
      ['delivered', 'completed'].contains(status) &&
      (deliveredAt == null ||
          DateTime.now().difference(deliveredAt!).inDays < 3);
  bool get isBuyOnBehalf => merchantType == 'buy_on_behalf';

  /// Đơn mua hộ đang chờ khách chọn tài xế (chưa từng chọn, hoặc tài xế trước đã từ chối).
  bool get needsDriverPick =>
      isBuyOnBehalf && status == 'ready_for_pickup' && selectedDriverId == null;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    orderCode: json['order_code'] as String? ?? '',
    merchantId: json['merchant_id'] as String,
    branchId: json['branch_id'] as String,
    status: json['status'] as String,
    salesModel: json['sales_model'] as String? ?? 'instant',
    shipRecipientName: json['ship_recipient_name'] as String? ?? '',
    shipRecipientPhone: json['ship_recipient_phone'] as String? ?? '',
    shipLine1: json['ship_line1'] as String? ?? '',
    shipProvince: json['ship_province'] as String? ?? '',
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
    deliveryFee: (json['delivery_fee'] as num?)?.toInt() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
    buyOnBehalfFee: (json['buy_on_behalf_fee'] as num?)?.toInt() ?? 0,
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
    deliveredAt: json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'].toString())
        : null,
    items:
        (json['items'] as List?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    merchantName: json['merchant_name'] as String?,
    merchantType: json['merchant_type'] as String?,
    selectedDriverId: json['selected_driver_id'] as String?,
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
