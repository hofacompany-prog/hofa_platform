import 'package:flutter/material.dart';

/// Nền gradient tươi xanh phía sau toàn bộ app — bọc ở main.dart nên áp dụng cho mọi màn
/// hình mà không cần sửa từng file. Pha nhạt từ màu chủ đạo (xanh lá) sang màu accent (cam)
/// trên nền trắng (sáng) hoặc gần đen (tối) để giữ độ tương phản, chữ/card phía trên vẫn rõ
/// ràng, chuyên nghiệp ở cả 2 giao diện.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  static const _primary = Color(0xFF85C100);
  static const _secondary = Color(0xFFFB8519);
  static const _darkBase = Color(0xFF10130C);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? _darkBase : Colors.white;
    final blendAlpha = isDark ? 0.22 : 0.16;
    final blendAlpha2 = isDark ? 0.14 : 0.10;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(_primary.withValues(alpha: blendAlpha), base),
                  base,
                  Color.alphaBlend(_secondary.withValues(alpha: blendAlpha2), base),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
