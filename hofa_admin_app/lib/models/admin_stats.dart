/// Khớp với GET /admin/stats (server/src/routes/admin.js).
/// Postgres trả COUNT(...) dưới dạng chuỗi nên phải parse chứ không ép kiểu thẳng.
int _toInt(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

class UserStats {
  final int total, customers, merchants, drivers, blocked;
  UserStats({required this.total, required this.customers, required this.merchants, required this.drivers, required this.blocked});
  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        total: _toInt(j['total']),
        customers: _toInt(j['customers']),
        merchants: _toInt(j['merchants']),
        drivers: _toInt(j['drivers']),
        blocked: _toInt(j['blocked']),
      );
}

class MerchantStats {
  final int total, active, pendingReview, paused;
  MerchantStats({required this.total, required this.active, required this.pendingReview, required this.paused});
  factory MerchantStats.fromJson(Map<String, dynamic> j) => MerchantStats(
        total: _toInt(j['total']),
        active: _toInt(j['active']),
        pendingReview: _toInt(j['pending_review']),
        paused: _toInt(j['paused']),
      );
}

class OrderStats {
  final int total, today, inProgress, cancelled;
  OrderStats({required this.total, required this.today, required this.inProgress, required this.cancelled});
  factory OrderStats.fromJson(Map<String, dynamic> j) => OrderStats(
        total: _toInt(j['total']),
        today: _toInt(j['today']),
        inProgress: _toInt(j['in_progress']),
        cancelled: _toInt(j['cancelled']),
      );
}

class RevenueStats {
  final int gross, commission;
  RevenueStats({required this.gross, required this.commission});
  factory RevenueStats.fromJson(Map<String, dynamic> j) =>
      RevenueStats(gross: _toInt(j['gross']), commission: _toInt(j['commission']));
}

class RecentOrder {
  final String id, orderCode, status, merchantName, customerName;
  final int totalAmount;
  final DateTime createdAt;
  RecentOrder({
    required this.id,
    required this.orderCode,
    required this.status,
    required this.merchantName,
    required this.customerName,
    required this.totalAmount,
    required this.createdAt,
  });
  factory RecentOrder.fromJson(Map<String, dynamic> j) => RecentOrder(
        id: j['id'] as String,
        orderCode: j['order_code'] as String? ?? '',
        status: j['status'] as String? ?? '',
        merchantName: j['merchant_name'] as String? ?? '',
        customerName: j['customer_name'] as String? ?? '',
        totalAmount: _toInt(j['total_amount']),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class AdminStats {
  final UserStats users;
  final MerchantStats merchants;
  final OrderStats orders;
  final RevenueStats revenue;
  final List<RecentOrder> recentOrders;

  AdminStats({
    required this.users,
    required this.merchants,
    required this.orders,
    required this.revenue,
    required this.recentOrders,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        users: UserStats.fromJson(j['users'] as Map<String, dynamic>),
        merchants: MerchantStats.fromJson(j['merchants'] as Map<String, dynamic>),
        orders: OrderStats.fromJson(j['orders'] as Map<String, dynamic>),
        revenue: RevenueStats.fromJson(j['revenue'] as Map<String, dynamic>),
        recentOrders:
            (j['recent_orders'] as List?)?.map((e) => RecentOrder.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      );
}
