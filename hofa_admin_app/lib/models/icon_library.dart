/// 1 thư viện Iconify admin đã bật để tìm icon online ở màn Icon tabbar — khớp bảng
/// icon_libraries (xem hofa-db/54_icon_libraries.sql, GET /icon-libraries).
class IconLibrary {
  final String prefix;
  final String name;

  IconLibrary({required this.prefix, required this.name});

  factory IconLibrary.fromJson(Map<String, dynamic> json) => IconLibrary(
        prefix: json['prefix'] as String,
        name: json['name'] as String,
      );
}
