import 'package:flutter/material.dart';

/// Nguồn duy nhất cho danh sách mục điều hướng chính — dùng chung cho NavigationRail (màn
/// rộng), BottomNavigationBar (màn hẹp/điện thoại) trong DashboardShell, VÀ lưới lối tắt ở
/// màn Trang chủ, để không bị lệch nhau giữa các nơi khi thêm/bớt 1 mục.
typedef NavDestination = ({
  IconData icon,
  IconData selected,
  String label,
  String path,
});

const kNavDestinations = <NavDestination>[
  (
    icon: Icons.storefront_outlined,
    selected: Icons.storefront,
    label: 'Sản phẩm',
    path: '/products',
  ),
  (
    icon: Icons.receipt_long_outlined,
    selected: Icons.receipt_long,
    label: 'Đơn hàng',
    path: '/orders',
  ),
  (
    icon: Icons.inventory_2_outlined,
    selected: Icons.inventory_2,
    label: 'Kho hàng',
    path: '/inventory',
  ),
  (
    icon: Icons.category_outlined,
    selected: Icons.category,
    label: 'Danh mục',
    path: '/categories',
  ),
  (
    icon: Icons.settings_outlined,
    selected: Icons.settings,
    label: 'Cài đặt',
    path: '/settings',
  ),
];
