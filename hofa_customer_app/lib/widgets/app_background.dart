import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final topInset = MediaQuery.of(context).padding.top;
    // Dải trên cùng nền xanh thương hiệu đặc — icon giờ/pin/sóng của hệ thống phải là màu
    // SÁNG mới tương phản rõ trên nền xanh đậm này (ngược với lúc nền trắng).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS (dark = icon sáng)
      ),
      child: Stack(
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
          // Dải nền đặc riêng đúng chiều cao vùng an toàn trên cùng (nơi hệ thống vẽ giờ/pin/
          // sóng đè lên) — tô hẳn màu chủ đạo cho khác biệt rõ với phần nội dung, cùng icon
          // sáng màu ở trên cho tương phản chắc chắn, không phụ thuộc từng thiết bị.
          if (topInset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset,
              child: const ColoredBox(color: _primary),
            ),
          child,
        ],
      ),
    );
  }
}
