/// Số liệu nhanh cho màn Trang chủ (GET /merchants/:id/stats/today) — không cache lâu,
/// luôn refetch mỗi khi mở màn Trang chủ vì thay đổi liên tục theo đơn hàng thật.
class MerchantTodayStats {
  final int preparingCount;
  final int todayOrderCount;
  final int todayRevenue;

  MerchantTodayStats({
    required this.preparingCount,
    required this.todayOrderCount,
    required this.todayRevenue,
  });

  factory MerchantTodayStats.fromJson(Map<String, dynamic> json) => MerchantTodayStats(
        preparingCount: (json['preparing_count'] as num?)?.toInt() ?? 0,
        todayOrderCount: (json['today_order_count'] as num?)?.toInt() ?? 0,
        todayRevenue: (json['today_revenue'] as num?)?.toInt() ?? 0,
      );
}
