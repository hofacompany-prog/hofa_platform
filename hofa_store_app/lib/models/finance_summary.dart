/// Tóm tắt tài chính 1 khoảng thời gian (GET /merchants/:id/finance/summary) — doanh thu ròng
/// (loại đơn huỷ/hoàn tiền) trừ hoa hồng HOFA và thuế GTGT/TNCN (áp thẳng lên doanh thu ròng,
/// không lồng thuế trong thuế) ra thu nhập ròng.
class FinanceSummary {
  final String period;
  final DateTime from;
  final DateTime to;
  final int orderCount;
  final int revenue;
  final num commissionRate;
  final int commissionAmount;
  final num vatRate;
  final int vatAmount;
  final num pitRate;
  final int pitAmount;
  final int netIncome;

  FinanceSummary({
    required this.period,
    required this.from,
    required this.to,
    required this.orderCount,
    required this.revenue,
    required this.commissionRate,
    required this.commissionAmount,
    required this.vatRate,
    required this.vatAmount,
    required this.pitRate,
    required this.pitAmount,
    required this.netIncome,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) => FinanceSummary(
    period: json['period'] as String? ?? 'today',
    from: DateTime.tryParse(json['from']?.toString() ?? '') ?? DateTime.now(),
    to: DateTime.tryParse(json['to']?.toString() ?? '') ?? DateTime.now(),
    orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
    revenue: (json['revenue'] as num?)?.toInt() ?? 0,
    commissionRate: num.tryParse('${json['commission_rate']}') ?? 0,
    commissionAmount: (json['commission_amount'] as num?)?.toInt() ?? 0,
    vatRate: num.tryParse('${json['vat_rate']}') ?? 0,
    vatAmount: (json['vat_amount'] as num?)?.toInt() ?? 0,
    pitRate: num.tryParse('${json['pit_rate']}') ?? 0,
    pitAmount: (json['pit_amount'] as num?)?.toInt() ?? 0,
    netIncome: (json['net_income'] as num?)?.toInt() ?? 0,
  );
}

/// Chip lọc khoảng thời gian ở màn Tài chính — 'week' = từ đầu tuần (thứ Hai) tới hôm nay.
const financePeriodLabels = {'today': 'Hôm nay', 'yesterday': 'Hôm qua', 'week': 'Tuần này'};
