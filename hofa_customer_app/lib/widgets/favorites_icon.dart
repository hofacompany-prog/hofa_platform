import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/require_login.dart';

/// Icon trái tim ở AppBar trang chủ — mở màn "Cửa hàng yêu thích". Không cần biết trạng thái
/// yêu thích cụ thể (đó là việc của FavoriteButton trên từng thẻ/màn chi tiết cửa hàng), icon
/// này chỉ là lối vào, giống hệt cách NotificationBell mở hộp thư thông báo.
class FavoritesIcon extends StatelessWidget {
  const FavoritesIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Cửa hàng yêu thích',
      padding: const EdgeInsets.symmetric(horizontal: 6),
      onPressed: () async {
        if (!await requireLogin(context)) return;
        if (context.mounted) context.push('/favorites');
      },
      icon: const Icon(Icons.favorite_border),
    );
  }
}
