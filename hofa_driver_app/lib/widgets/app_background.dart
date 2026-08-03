import 'package:flutter/material.dart';

/// Nền gradient tươi xanh phía sau toàn bộ app — bọc ở main.dart nên áp dụng cho mọi màn
/// hình mà không cần sửa từng file. Pha nhạt từ màu chủ đạo (xanh lá) sang màu accent (cam)
/// trên nền trắng để giữ độ tương phản, chữ/card phía trên vẫn rõ ràng, chuyên nghiệp.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  static const _primary = Color(0xFF85C100);
  static const _secondary = Color(0xFFFB8519);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(_primary.withValues(alpha: 0.16), Colors.white),
                  Colors.white,
                  Color.alphaBlend(_secondary.withValues(alpha: 0.10), Colors.white),
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
