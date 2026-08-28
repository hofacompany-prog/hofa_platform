import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/require_login.dart';

/// Icon lịch sử đơn hàng ở AppBar trang chủ — mở màn "Đơn hàng của tôi", cùng đích với tab
/// "Đơn hàng" ở thanh điều hướng dưới, chỉ là lối vào nhanh hơn ngay từ trang chủ.
class OrderHistoryIcon extends StatelessWidget {
  const OrderHistoryIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Đơn hàng của tôi',
      padding: const EdgeInsets.symmetric(horizontal: 6),
      onPressed: () async {
        if (!await requireLogin(context)) return;
        if (context.mounted) context.push('/orders');
      },
      icon: const Icon(Icons.receipt_long_outlined),
    );
  }
}
