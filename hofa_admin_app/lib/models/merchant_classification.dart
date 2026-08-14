/// 1 phân loại cửa hàng (vd "Nhà hàng", "Cà phê", "Siêu thị mini") — admin tự quản lý danh sách,
/// 1 cửa hàng gắn được nhiều phân loại cùng lúc. Khác hẳn `Category` (danh mục ngành hàng sản
/// phẩm) và `MerchantCategory` (mục thực đơn tự đặt riêng của từng cửa hàng).
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
