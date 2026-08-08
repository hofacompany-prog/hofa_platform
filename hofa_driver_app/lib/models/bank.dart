/// 1 dòng trong danh sách ngân hàng admin quản lý — hiện thành dropdown lúc đăng ký/sửa hồ sơ.
class Bank {
  final String id;
  final String name;
  final String bin;

  Bank({required this.id, required this.name, required this.bin});

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        bin: json['bin'] as String? ?? '',
      );
}
