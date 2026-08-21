/// Báo cáo sự cố nội bộ giữa tài xế/cửa hàng theo từng đơn — xem
/// server/src/routes/issue-reports.js, hofa-db/92_issue_reports.sql.
class IssueReport {
  final String id;
  final String orderId;
  final String orderCode;
  final String merchantId;
  final String merchantName;
  final String reporterType; // 'driver' | 'merchant'
  final String reporterId;
  final String? reporterName;
  final String? reporterPhone;
  final String? customerName;
  final List<String> issueTypes;
  final int? waitMinutes;
  final String? note;
  final int? customerRating;
  final String status; // 'open' | 'resolved'
  final String? adminNote;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  IssueReport({
    required this.id,
    required this.orderId,
    required this.orderCode,
    required this.merchantId,
    required this.merchantName,
    required this.reporterType,
    required this.reporterId,
    this.reporterName,
    this.reporterPhone,
    this.customerName,
    this.issueTypes = const [],
    this.waitMinutes,
    this.note,
    this.customerRating,
    required this.status,
    this.adminNote,
    this.resolvedAt,
    required this.createdAt,
  });

  bool get isDriverReport => reporterType == 'driver';

  factory IssueReport.fromJson(Map<String, dynamic> j) => IssueReport(
    id: j['id'] as String,
    orderId: j['order_id'] as String,
    orderCode: j['order_code'] as String? ?? '',
    merchantId: j['merchant_id'] as String,
    merchantName: j['merchant_name'] as String? ?? '',
    reporterType: j['reporter_type'] as String,
    reporterId: j['reporter_id'] as String,
    reporterName: j['reporter_name'] as String?,
    reporterPhone: j['reporter_phone'] as String?,
    customerName: j['customer_name'] as String?,
    issueTypes: j['issue_types'] is List
        ? (j['issue_types'] as List).map((e) => e.toString()).toList()
        : const [],
    waitMinutes: (j['wait_minutes'] as num?)?.toInt(),
    note: j['note'] as String?,
    customerRating: (j['customer_rating'] as num?)?.toInt(),
    status: j['status'] as String? ?? 'open',
    adminNote: j['admin_note'] as String?,
    resolvedAt: j['resolved_at'] != null
        ? DateTime.tryParse(j['resolved_at'].toString())
        : null,
    createdAt:
        DateTime.tryParse(j['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

/// Nhãn tiếng Việt cho từng mã vấn đề — khớp DRIVER_ISSUE_TYPES/MERCHANT_ISSUE_TYPES ở
/// server/src/routes/issue-reports.js.
const driverIssueLabels = {
  'slow': 'Cửa hàng làm lâu',
  'no_parking': 'Không có chỗ để xe',
  'other': 'Khác',
};

const merchantIssueLabels = {
  'late': 'Tài xế đến trễ',
  'attitude': 'Thái độ không tốt',
  'no_show': 'Không tới lấy hàng',
  'other': 'Khác',
};

String issueTypeLabel(String reporterType, String type) =>
    (reporterType == 'driver' ? driverIssueLabels : merchantIssueLabels)[type] ??
    type;
