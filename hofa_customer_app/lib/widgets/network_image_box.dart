import 'package:flutter/material.dart';

/// Ảnh mạng có fallback icon khi thiếu URL hoặc load lỗi — dùng chung cho card
/// cửa hàng/sản phẩm vì dữ liệu ảnh do người bán tự nhập, không đảm bảo luôn hợp lệ.
class NetworkImageBox extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  const NetworkImageBox({
    super.key,
    this.url,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackIcon = Icons.image_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(12);
    final theme = Theme.of(context);
    Widget fallback() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: radius),
          child: Icon(fallbackIcon, color: theme.colorScheme.outline),
        );

    if (url == null || url!.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
        loadingBuilder: (context, child, progress) => progress == null ? child : fallback(),
      ),
    );
  }
}
