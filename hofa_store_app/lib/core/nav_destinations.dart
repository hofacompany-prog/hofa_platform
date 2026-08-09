import 'package:flutter/material.dart';

/// Nguồn duy nhất cho danh sách mục điều hướng chính — dùng chung cho NavigationRail (màn
/// rộng), BottomNavigationBar (màn hẹp/điện thoại) trong DashboardShell, VÀ lưới lối tắt ở
/// màn Trang chủ, để không bị lệch nhau giữa các nơi khi thêm/bớt 1 mục.
typedef NavDestination = ({
  String tabKey,
  IconData icon,
  IconData selected,
  String label,
  String path,
});

const kNavDestinations = <NavDestination>[
  (
    tabKey: 'products',
    icon: Icons.storefront_outlined,
    selected: Icons.storefront,
    label: 'Sản phẩm',
    path: '/products',
  ),
  (
    tabKey: 'orders',
    icon: Icons.receipt_long_outlined,
    selected: Icons.receipt_long,
    label: 'Đơn hàng',
    path: '/orders',
  ),
  (
    tabKey: 'finance',
    icon: Icons.account_balance_wallet_outlined,
    selected: Icons.account_balance_wallet,
    label: 'Tài chính',
    path: '/finance',
  ),
  (
    tabKey: 'settings',
    icon: Icons.settings_outlined,
    selected: Icons.settings,
    label: 'Cài đặt',
    path: '/settings',
  ),
];
