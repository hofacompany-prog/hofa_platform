/// 1 lần tài xế nộp lại tiền COD (gồm nhiều đơn) — xem GET /admin/driver-cod-settlements,
/// hofa-db/62_driver_wallet_ledger.sql.
class CodSettlementRequest {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhone;
  final int totalAmount;
  final String status;
  final String? proofImageUrl;
  final int orderCount;
  final DateTime createdAt;
  final String? rejectReason;

  CodSettlementRequest({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverPhone,
    required this.totalAmount,
    required this.status,
    this.proofImageUrl,
    required this.orderCount,
    required this.createdAt,
    this.rejectReason,
  });

  factory CodSettlementRequest.fromJson(
    Map<String, dynamic> json,
  ) => CodSettlementRequest(
    id: json['id'] as String,
    driverId: json['driver_id'] as String,
    driverName: json['driver_name'] as String? ?? '',
    driverPhone: json['driver_phone'] as String?,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'pending',
    proofImageUrl: json['proof_image_url'] as String?,
    // COUNT(*) trả về BIGINT trong Postgres — node-postgres trả BIGINT dưới dạng String,
    // không phải num (cùng lý do driver_wallet_summary.dart).
    orderCount: int.tryParse('${json['order_count']}') ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now(),
    rejectReason: json['reject_reason'] as String?,
  );
}
