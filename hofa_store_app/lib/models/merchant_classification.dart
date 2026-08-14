/// 1 phân loại cửa hàng (vd "Nhà hàng", "Cà phê", "Siêu thị mini") — admin quản lý danh sách,
/// cửa hàng tự gắn nhiều phân loại cùng lúc cho hồ sơ của mình.
class MerchantClassification {
  final String id;
  final String name;
  final int sortOrder;

  MerchantClassification({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory MerchantClassification.fromJson(Map<String, dynamic> json) =>
      MerchantClassification(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}
