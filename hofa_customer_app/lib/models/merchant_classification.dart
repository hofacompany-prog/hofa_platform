/// 1 phân loại cửa hàng (vd "Nhà hàng", "Cà phê", "Siêu thị mini") — khách lọc cửa hàng theo
/// đây ở trang chủ (nhiều lựa chọn cùng lúc).
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
