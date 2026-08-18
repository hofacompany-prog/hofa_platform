/// 1 báo cáo giá sai từ khách/tài xế — xem GET /admin/price-reports,
/// hofa-db/89_product_price_reports.sql.
class PriceReport {
  final String id;
  final String variantId;
  final String variantName;
  final int currentPrice;
  final String productName;
  final String merchantId;
  final String merchantName;
  final String reporterName;
  final String? reporterPhone;
  final String reporterRole;
  final int priceAtReport;
  final int reportedPrice;
  final String status;
  final int? finalPrice;
  final DateTime createdAt;

  PriceReport({
    required this.id,
    required this.variantId,
    required this.variantName,
    required this.currentPrice,
    required this.productName,
    required this.merchantId,
    required this.merchantName,
    required this.reporterName,
    this.reporterPhone,
    required this.reporterRole,
    required this.priceAtReport,
    required this.reportedPrice,
    required this.status,
    this.finalPrice,
    required this.createdAt,
  });

  factory PriceReport.fromJson(Map<String, dynamic> json) => PriceReport(
    id: json['id'] as String,
    variantId: json['variant_id'] as String,
    variantName: json['variant_name'] as String? ?? '',
    currentPrice: (json['current_price'] as num?)?.toInt() ?? 0,
    productName: json['product_name'] as String? ?? '',
    merchantId: json['merchant_id'] as String,
    merchantName: json['merchant_name'] as String? ?? '',
    reporterName: json['reporter_name'] as String? ?? '',
    reporterPhone: json['reporter_phone'] as String?,
    reporterRole: json['reporter_role'] as String? ?? '',
    priceAtReport: (json['price_at_report'] as num?)?.toInt() ?? 0,
    reportedPrice: (json['reported_price'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'pending',
    finalPrice: (json['final_price'] as num?)?.toInt(),
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}
