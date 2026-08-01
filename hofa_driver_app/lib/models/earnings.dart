class RecentDelivery {
  final int driverFee;
  final DateTime? deliveredAt;

  RecentDelivery({required this.driverFee, this.deliveredAt});

  factory RecentDelivery.fromJson(Map<String, dynamic> json) => RecentDelivery(
        driverFee: (json['driver_fee'] as num?)?.toInt() ?? 0,
        deliveredAt: json['delivered_at'] != null ? DateTime.tryParse(json['delivered_at'] as String) : null,
      );
}

class Earnings {
  final int walletBalance;
  final int totalDeliveries;
  final num ratingAvg;
  final int ratingCount;
  final List<RecentDelivery> recentDeliveries;

  Earnings({
    required this.walletBalance,
    required this.totalDeliveries,
    required this.ratingAvg,
    required this.ratingCount,
    required this.recentDeliveries,
  });

  int get todayTotal {
    final now = DateTime.now();
    return recentDeliveries
        .where((d) => d.deliveredAt != null && d.deliveredAt!.year == now.year && d.deliveredAt!.month == now.month && d.deliveredAt!.day == now.day)
        .fold(0, (sum, d) => sum + d.driverFee);
  }

  factory Earnings.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final recent = json['recent_deliveries'] as List? ?? [];
    return Earnings(
      walletBalance: (summary['wallet_balance'] as num?)?.toInt() ?? 0,
      totalDeliveries: (summary['total_deliveries'] as num?)?.toInt() ?? 0,
      ratingAvg: num.tryParse('${summary['rating_avg']}') ?? 0,
      ratingCount: (summary['rating_count'] as num?)?.toInt() ?? 0,
      recentDeliveries: recent.map((e) => RecentDelivery.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
