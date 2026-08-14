/// Số giờ được nhắn tin thêm sau khi đơn giao xong — hết giờ thì app tự ẩn lối vào nhắn tin,
/// xem hofa-db/74_order_chat.sql.
class ChatSettings {
  final String? id;
  final int hoursAfterDelivered;

  ChatSettings({this.id, required this.hoursAfterDelivered});

  factory ChatSettings.fromJson(Map<String, dynamic> json) => ChatSettings(
    id: json['id'] as String?,
    hoursAfterDelivered: (json['hours_after_delivered'] as num?)?.toInt() ?? 1,
  );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory ChatSettings.fallback() => ChatSettings(hoursAfterDelivered: 1);

  Map<String, dynamic> toJson() => {
    'hours_after_delivered': hoursAfterDelivered,
  };
}
