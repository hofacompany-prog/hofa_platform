/// 1 dòng trong danh sách ngân hàng admin tự quản lý — tài xế chọn từ đây lúc đăng ký/sửa hồ sơ.
class Bank {
  final String id;
  final String name;
  final String bin;
  final int sortOrder;

  Bank({required this.id, required this.name, required this.bin, required this.sortOrder});

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        bin: json['bin'] as String? ?? '',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}
