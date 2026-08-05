/// Chữ đầu (prefix) của mã đơn hàng hiển thị (order_code), vd 'HF' -> 'HF-482'.
/// 2 loại theo sales_model: instant (giao ngay) và scheduled (đặt trước/giá sỉ).
class OrderSettings {
  final String? id;
  final String codePrefixInstant;
  final String codePrefixScheduled;

  OrderSettings({
    this.id,
    required this.codePrefixInstant,
    required this.codePrefixScheduled,
  });

  factory OrderSettings.fromJson(Map<String, dynamic> json) => OrderSettings(
    id: json['id'] as String?,
    codePrefixInstant: json['code_prefix_instant'] as String? ?? 'HF',
    codePrefixScheduled: json['code_prefix_scheduled'] as String? ?? 'DT',
  );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory OrderSettings.fallback() =>
      OrderSettings(codePrefixInstant: 'HF', codePrefixScheduled: 'DT');

  Map<String, dynamic> toJson() => {
    'code_prefix_instant': codePrefixInstant,
    'code_prefix_scheduled': codePrefixScheduled,
  };
}
