/// SĐT liên hệ admin/hỗ trợ toàn sàn (đặt ở app admin) — gọi/nhắn tin thẳng số này ở nút
/// "Liên hệ hỗ trợ" trên màn chi tiết cửa hàng MUA HỘ, vì cửa hàng mua hộ không trực tiếp xử
/// lý đơn (tài xế tự đi mua).
class AdminContactSettings {
  final String? phone;

  AdminContactSettings({this.phone});

  bool get isConfigured => phone != null && phone!.trim().isNotEmpty;

  factory AdminContactSettings.fromJson(Map<String, dynamic> json) =>
      AdminContactSettings(phone: json['phone'] as String?);

  factory AdminContactSettings.empty() => AdminContactSettings();
}
