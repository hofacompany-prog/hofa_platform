/// Công tắc toàn sàn ẩn/hiện "Đặt trước/Bán sỉ" (sales_model='scheduled') ở app Khách hàng —
/// tắt thì GET /products tự lọc bỏ hết sản phẩm loại này khỏi mọi kết quả khách duyệt/tìm
/// kiếm, không đụng tới dữ liệu sản phẩm/đơn hàng cũ. Xem
/// hofa-db/110_wholesale_preorder_toggle.sql.
class WholesalePreorderSettings {
  final String? id;
  final bool enabled;

  WholesalePreorderSettings({this.id, required this.enabled});

  factory WholesalePreorderSettings.fromJson(Map<String, dynamic> json) =>
      WholesalePreorderSettings(
        id: json['id'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory WholesalePreorderSettings.fallback() =>
      WholesalePreorderSettings(enabled: true);

  Map<String, dynamic> toJson() => {'enabled': enabled};
}
