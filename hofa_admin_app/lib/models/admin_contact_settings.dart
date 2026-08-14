/// SĐT liên hệ admin/hỗ trợ toàn sàn — app khách gọi/nhắn tin thẳng số này ở nút "Liên hệ hỗ
/// trợ" trên màn chi tiết cửa hàng MUA HỘ (cửa hàng mua hộ không trực tiếp xử lý đơn, khách
/// cần liên hệ admin thay vì cửa hàng).
class AdminContactSettings {
  final String? id;
  final String? phone;

  AdminContactSettings({this.id, this.phone});

  factory AdminContactSettings.fromJson(Map<String, dynamic> json) =>
      AdminContactSettings(
        id: json['id'] as String?,
        phone: json['phone'] as String?,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration/lưu lần nào).
  factory AdminContactSettings.fallback() => AdminContactSettings();

  Map<String, dynamic> toJson() => {'phone': phone};
}
