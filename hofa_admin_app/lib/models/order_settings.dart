/// Chữ đầu (prefix) của mã đơn hàng hiển thị (order_code), vd 'HF' -> 'HF-482'.
class OrderSettings {
  final String? id;
  final String codePrefix;

  OrderSettings({this.id, required this.codePrefix});

  factory OrderSettings.fromJson(Map<String, dynamic> json) => OrderSettings(
    id: json['id'] as String?,
    codePrefix: json['code_prefix'] as String? ?? 'HF',
  );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory OrderSettings.fallback() => OrderSettings(codePrefix: 'HF');

  Map<String, dynamic> toJson() => {'code_prefix': codePrefix};
}
