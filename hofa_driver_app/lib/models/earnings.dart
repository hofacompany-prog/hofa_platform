class RecentDelivery {
  final int driverFee;
  // Chốt lúc giao xong — driverPayout = driverFee - commissionAmount - vatAmount - pitAmount,
  // đúng bằng số tiền thực tế cộng vào ví. Xem hofa-db/72_driver_tax_rates.sql.
  final int commissionAmount;
  final int vatAmount;
  final int pitAmount;
  final int driverPayout;
  // % phí mua hộ được chia, chốt lúc giao xong — xem
  // hofa-db/79_driver_buy_on_behalf_fee_share.sql.
  final int buyOnBehalfFeeShareAmount;
  final DateTime? deliveredAt;
  final String orderCode;
  final bool isCod;
  final int totalAmount;

  RecentDelivery({
    required this.driverFee,
    this.commissionAmount = 0,
    this.vatAmount = 0,
    this.pitAmount = 0,
    this.driverPayout = 0,
    this.buyOnBehalfFeeShareAmount = 0,
    this.deliveredAt,
    required this.orderCode,
    required this.isCod,
    required this.totalAmount,
  });

  factory RecentDelivery.fromJson(Map<String, dynamic> json) => RecentDelivery(
    driverFee: (json['driver_fee'] as num?)?.toInt() ?? 0,
    commissionAmount: (json['commission_amount'] as num?)?.toInt() ?? 0,
    vatAmount: (json['vat_amount'] as num?)?.toInt() ?? 0,
    pitAmount: (json['pit_amount'] as num?)?.toInt() ?? 0,
    driverPayout: (json['driver_payout'] as num?)?.toInt() ?? 0,
    buyOnBehalfFeeShareAmount:
        (json['buy_on_behalf_fee_share_amount'] as num?)?.toInt() ?? 0,
    deliveredAt: json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'] as String)
        : null,
    orderCode: json['order_code'] as String? ?? '',
    isCod: json['is_cod'] as bool? ?? false,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
  );
}

/// Tổng hôm nay (giờ Việt Nam) — chốt sẵn từ server, không tự cộng dồn phía Flutter, xem
/// GET /drivers/me/earnings.
class TodayEarnings {
  final int gross;
  final int commissionAmount;
  final int vatAmount;
  final int pitAmount;
  final int net;
  final int buyOnBehalfFeeShareAmount;

  TodayEarnings({
    required this.gross,
    required this.commissionAmount,
    required this.vatAmount,
    required this.pitAmount,
    required this.net,
    this.buyOnBehalfFeeShareAmount = 0,
  });

  factory TodayEarnings.fromJson(Map<String, dynamic>? json) => TodayEarnings(
    gross: (json?['gross'] as num?)?.toInt() ?? 0,
    commissionAmount: (json?['commission_amount'] as num?)?.toInt() ?? 0,
    vatAmount: (json?['vat_amount'] as num?)?.toInt() ?? 0,
    pitAmount: (json?['pit_amount'] as num?)?.toInt() ?? 0,
    net: (json?['net'] as num?)?.toInt() ?? 0,
    buyOnBehalfFeeShareAmount:
        (json?['buy_on_behalf_fee_share_amount'] as num?)?.toInt() ?? 0,
  );
}

/// Ví tài xế — TÁCH 2 ví riêng (xem hofa-db/69_driver_wallet_vi_tren.sql): codBalance là **Ví
/// trên** (vốn để nhận đơn mới, trừ tự động khi giao đơn xong, KHÔNG rút/chuyển đi đâu được),
/// earningBalance là **Ví thu nhập** (tiền thật, rút được về ngân hàng).
class Earnings {
  final int codBalance;
  final int earningBalance;
  final int totalDeliveries;
  final num ratingAvg;
  final int ratingCount;
  final List<RecentDelivery> recentDeliveries;
  final TodayEarnings today;

  Earnings({
    required this.codBalance,
    required this.earningBalance,
    required this.totalDeliveries,
    required this.ratingAvg,
    required this.ratingCount,
    required this.recentDeliveries,
    required this.today,
  });

  factory Earnings.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final recent = json['recent_deliveries'] as List? ?? [];
    return Earnings(
      today: TodayEarnings.fromJson(json['today'] as Map<String, dynamic>?),
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

/// Nhãn tiếng Việt cho từng loại giao dịch — dùng ở màn "Lịch sử ví". cod_collected/cod_settled/
/// earning_released không còn phát sinh mới (giữ nhãn để hiện đúng lịch sử cũ trước migration
/// hofa-db/69_driver_wallet_vi_tren.sql).
const walletEntryTypeLabels = {
  'cod_collected': 'Thu COD (cũ)',
  'cod_settled': 'Đã nộp COD (cũ)',
  'earning_released': 'Phí giao hàng (cũ)',
  'order_deducted': 'Trừ vốn đơn hàng',
  'order_payment_received': 'Tiền đơn hàng',
  'buy_on_behalf_reimbursement': 'Hoàn tiền mua hộ',
  'buy_on_behalf_fee_share': 'Phí mua hộ được chia',
  'withdrawal': 'Rút tiền',
  'withdrawal_rejected': 'Hoàn tiền rút bị từ chối',
  'admin_adjustment': 'HOFA điều chỉnh',
  'deposit': 'Nạp tiền',
  'earning_transfer_out': 'Chuyển sang Ví trên',
  'earning_transfer_in': 'Nhận từ Ví thu nhập',
};
