import 'package:flutter/material.dart';

/// Icon tabbar — hiện ảnh tuỳ chỉnh (chọn ở web admin) nếu có, không thì rơi về icon Material
/// mặc định. [color] luôn truyền rõ từ nơi gọi (không đọc IconTheme.of(context) — đã xác nhận
/// NavigationBar không tô đúng màu cho widget con tuỳ ý qua IconThemeData ambient như kỳ
/// vọng, chỉ đáng tin cậy với Icon() dựng sẵn).
class TabIcon extends StatelessWidget {
  final String? url;
  final IconData fallback;
  final Color color;
  final double size;
  const TabIcon({super.key, this.url, required this.fallback, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return Icon(fallback, size: size, color: color);
    // Glyph icon Material thường có khoảng đệm sẵn trong chính glyph (nhìn nhỏ hơn khung),
    // trong khi icon SVG thư viện (Lucide/Iconify) vẽ gần sát viền khung — cùng 1 kích thước
    // khung thì icon thư viện trông to/đậm hơn hẳn icon Material bên cạnh. Vẽ nhỏ hơn khung
    // 1 chút (0.8x) để cân bằng lại độ lớn nhìn bằng mắt cho khớp các tab còn lại.
    return Image.network(
      url!,
      width: size * 0.8,
      height: size * 0.8,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (_, _, _) => Icon(fallback, size: size, color: color),
    );
  }
}
