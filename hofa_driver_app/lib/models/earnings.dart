class RecentDelivery {
  final int driverFee;
  final DateTime? deliveredAt;
  final String orderCode;
  final bool isCod;
  final int totalAmount;
  // true nếu đơn COD này đã nằm trong 1 lần nộp COD đang chờ duyệt/đã duyệt — không cần nộp lại.
  final bool codSettledOrPending;

  RecentDelivery({
    required this.driverFee,
    this.deliveredAt,
    required this.orderCode,
    required this.isCod,
    required this.totalAmount,
    required this.codSettledOrPending,
  });

  factory RecentDelivery.fromJson(Map<String, dynamic> json) => RecentDelivery(
    driverFee: (json['driver_fee'] as num?)?.toInt() ?? 0,
    deliveredAt: json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'] as String)
        : null,
    orderCode: json['order_code'] as String? ?? '',
    isCod: json['is_cod'] as bool? ?? false,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    codSettledOrPending: json['cod_settled_or_pending'] as bool? ?? false,
  );
}

/// Ví tài xế — TÁCH 2 ví riêng (xem hofa-db/62_driver_wallet_ledger.sql): codBalance là tiền
/// COD đang giữ hộ khách/HOFA (không rút được, chỉ nộp lại qua "Nộp COD"), earningBalance là
/// thu nhập thực sự có thể rút.
class Earnings {
  final int codBalance;
  final int earningBalance;
  final int totalDeliveries;
  final num ratingAvg;
  final int ratingCount;
  final List<RecentDelivery> recentDeliveries;

  Earnings({
    required this.codBalance,
    required this.earningBalance,
    required this.totalDeliveries,
    required this.ratingAvg,
    required this.ratingCount,
    required this.recentDeliveries,
  });

  int get todayTotal {
    final now = DateTime.now();
    return recentDeliveries
        .where(
          (d) =>
              d.deliveredAt != null &&
              d.deliveredAt!.year == now.year &&
              d.deliveredAt!.month == now.month &&
              d.deliveredAt!.day == now.day,
        )
        .fold(0, (sum, d) => sum + d.driverFee);
  }

  factory Earnings.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final recent = json['recent_deliveries'] as List? ?? [];
    return Earnings(
      codBalance: (summary['cod_balance'] as num?)?.toInt() ?? 0,
      earningBalance: (summary['earning_balance'] as num?)?.toInt() ?? 0,
      totalDeliveries: (summary['total_deliveries'] as num?)?.toInt() ?? 0,
      ratingAvg: num.tryParse('${summary['rating_avg']}') ?? 0,
      ratingCount: (summary['rating_count'] as num?)?.toInt() ?? 0,
      recentDeliveries: recent
          .map((e) => RecentDelivery.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CodPendingOrder {
  final String orderId;
  final String orderCode;
  final int totalAmount;
  final DateTime? deliveredAt;

  CodPendingOrder({
    required this.orderId,
    required this.orderCode,
    required this.totalAmount,
    this.deliveredAt,
  });

  factory CodPendingOrder.fromJson(Map<String, dynamic> json) =>
      CodPendingOrder(
        orderId: json['order_id'] as String,
        orderCode: json['order_code'] as String? ?? '',
        totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
        deliveredAt: json['delivered_at'] != null
            ? DateTime.tryParse(json['delivered_at'] as String)
            : null,
      );
}

class WalletTransaction {
  final String id;
  final String wallet; // 'cod' | 'earning'
  final String entryType;
  final int amount;
  final String? note;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.wallet,
    required this.entryType,
    required this.amount,
    this.note,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: json['id'] as String,
        wallet: json['wallet'] as String,
        entryType: json['entry_type'] as String,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Nhãn tiếng Việt cho từng loại giao dịch — dùng ở màn "Lịch sử ví".
const walletEntryTypeLabels = {
  'cod_collected': 'Thu COD',
  'cod_settled': 'Đã nộp COD',
  'earning_released': 'Phí giao hàng',
  'buy_on_behalf_reimbursement': 'Hoàn tiền mua hộ',
  'withdrawal': 'Rút tiền',
  'withdrawal_rejected': 'Hoàn tiền rút bị từ chối',
  'admin_adjustment': 'HOFA điều chỉnh',
};
