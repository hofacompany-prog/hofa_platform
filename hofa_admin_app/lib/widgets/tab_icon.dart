import 'package:flutter/material.dart';

/// Icon tabbar — hiện ảnh tuỳ chỉnh (chọn ở màn Icon tabbar) nếu có, không thì rơi về icon
/// Material mặc định. Tô màu bằng IconTheme.of(context).color thay vì tự tính theo trạng thái
/// chọn/chưa chọn — NavigationRail/NavigationBar tự set IconTheme khác nhau cho icon đang chọn
/// và chưa chọn, áp dụng cho MỌI widget con (không riêng gì Icon), nên chỉ cần đọc lại đúng màu
/// đó là khớp hệt hành vi icon Material gốc.
class TabIcon extends StatelessWidget {
  final String? url;
  final IconData fallback;
  const TabIcon({super.key, this.url, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    if (url == null || url!.isEmpty) return Icon(fallback, color: color);
    // Glyph icon Material thường có khoảng đệm sẵn trong chính glyph (nhìn nhỏ hơn khung),
    // trong khi icon SVG thư viện (Lucide/Iconify) vẽ gần sát viền khung — cùng 1 kích thước
    // khung thì icon thư viện trông to/đậm hơn hẳn icon Material bên cạnh. Vẽ nhỏ hơn khung
    // 1 chút (0.8x) để cân bằng lại độ lớn nhìn bằng mắt cho khớp các tab còn lại.
    return Image.network(
      url!,
      width: 24 * 0.8,
      height: 24 * 0.8,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (_, _, _) => Icon(fallback, color: color),
    );
  }
}
