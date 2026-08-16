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
    // fit: expand — BẮT BUỘC, không thì "child" (toàn bộ nội dung app phía trên nền) chỉ là 1
    // child KHÔNG positioned trong Stack, mặc định Stack dùng StackFit.loose nên child đó co
    // lại theo kích thước NỘI DUNG của chính nó thay vì lấp đầy màn hình — mọi thứ bị dồn vào
    // 1 cột hẹp ở góc trái, phần còn lại chỉ còn thấy màu nền (đã xảy ra thật, không phải giả
    // định — xem lúc thêm brightness-aware background cho dark mode).
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
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
        child,
      ],
    );
  }
}
