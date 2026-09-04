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
  final String salesModel;
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
  // Giờ hẹn giao cho đơn GIAO NGAY có đặt trước (salesModel='instant', khác đơn "Đặt trước/Giá
  // sỉ" salesModel='scheduled') — xem PATCH /orders/:id/scheduled-for. scheduledActivatedAt
  // khác null nghĩa là cửa hàng đã được báo (xem orderOffer.sweepDueScheduledInstant).
  final DateTime? scheduledFor;
  final DateTime? scheduledActivatedAt;
  final List<OrderItem> items;
  // Chỉ có khi gọi GET /admin/orders (server join sẵn để hiển thị thẳng trong bảng)
  final String? merchantName;
  final String? customerName;
  // Quét tìm tài xế (xem server/src/dispatch.js#sweepDriverSearch) — driverSearchAlertedAt
  // có giá trị nghĩa là đang chờ admin quyết định huỷ đơn hay quét tiếp.
  final int driverSearchAttempts;
  final DateTime? driverSearchAlertedAt;
  // 'buy_on_behalf' = đơn mua hộ, cần tài xế tự nhận hoặc khách/admin chỉ định — xem
  // POST /orders/:id/select-driver. deliveryDriverId null = CHƯA có ai nhận, dùng để hiện thẻ
  // "Quét tài xế"/"Chọn tài xế" ở order_detail_screen.dart bất kể có bị sweep báo động hay chưa.
  final String? merchantType;
  final String? selectedDriverId;
  final String? deliveryDriverId;

  Order({
    required this.id,
    required this.orderCode,
    required this.merchantId,
    required this.branchId,
    required this.status,
    this.salesModel = 'instant',
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
    this.scheduledFor,
    this.scheduledActivatedAt,
    required this.items,
    this.merchantName,
    this.customerName,
    this.driverSearchAttempts = 0,
    this.driverSearchAlertedAt,
    this.merchantType,
    this.selectedDriverId,
    this.deliveryDriverId,
  });

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
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    paymentMethod: json['payment_method'] as String? ?? 'cod',
    paymentStatus: json['payment_status'] as String? ?? 'pending',
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    scheduledFor: json['scheduled_for'] != null
        ? DateTime.tryParse(json['scheduled_for'].toString())
        : null,
    scheduledActivatedAt: json['scheduled_activated_at'] != null
        ? DateTime.tryParse(json['scheduled_activated_at'].toString())
        : null,
    items:
        (json['items'] as List?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    merchantName: json['merchant_name'] as String?,
    customerName: json['customer_name'] as String?,
    driverSearchAttempts:
        (json['driver_search_attempts'] as num?)?.toInt() ?? 0,
    driverSearchAlertedAt: json['driver_search_alerted_at'] != null
        ? DateTime.tryParse(json['driver_search_alerted_at'].toString())
        : null,
    merchantType: json['merchant_type'] as String?,
    selectedDriverId: json['selected_driver_id'] as String?,
    deliveryDriverId: json['delivery_driver_id'] as String?,
  );

  /// Tổng SỐ LƯỢNG món (cộng dồn quantity từng dòng) — khác items.length (chỉ đếm số DÒNG sản
  /// phẩm khác nhau, đơn "2x Cá basa" chỉ có 1 dòng nhưng phải hiện 2 món).
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);
}

/// Nhãn tiếng Việt + màu cho từng trạng thái — khớp enum order_status trong 01_schema.sql
const orderStatusLabels = {
  'pending_payment': 'Chờ thanh toán',
  'placed': 'Đơn mới',
  'confirmed': 'Đã xác nhận',
  'preparing': 'Đang chuẩn bị',
  'ready_for_pickup': 'Đang tìm tài xế',
  'assigned': 'Chờ tài xế lấy hàng',
  'picked_up': 'Đã lấy hàng',
  'delivering': 'Đang giao',
  'delivered': 'Đã giao',
  'completed': 'Hoàn tất',
  'cancelled': 'Đã huỷ',
  'refunded': 'Đã hoàn tiền',
};

/// Admin được ép chuyển sang bất kỳ trạng thái nào (p_force = true trong RPC update_order_status),
/// nên ở web admin ta cho chọn tự do thay vì cố định bước kế tiếp như bên app cửa hàng.
const allOrderStatuses = [
  'pending_payment',
  'placed',
  'confirmed',
  'preparing',
  'ready_for_pickup',
  'assigned',
  'picked_up',
  'delivering',
  'delivered',
  'completed',
  'cancelled',
  'refunded',
];
