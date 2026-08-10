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
  // null = luôn hiện (chủ cửa hàng lẫn mọi nhân viên) — dùng để ẩn tab với nhân viên không
  // được cấp quyền tương ứng, xem myPermissionsProvider/hasPermission trong auth_provider.dart.
  String? permission,
});

const kNavDestinations = <NavDestination>[
  (
    tabKey: 'products',
    icon: Icons.storefront_outlined,
    selected: Icons.storefront,
    label: 'Sản phẩm',
    path: '/products',
    permission: 'products.view',
  ),
  (
    tabKey: 'orders',
    icon: Icons.receipt_long_outlined,
    selected: Icons.receipt_long,
    label: 'Đơn hàng',
    path: '/orders',
    permission: 'orders.view',
  ),
  (
    tabKey: 'finance',
    icon: Icons.account_balance_wallet_outlined,
    selected: Icons.account_balance_wallet,
    label: 'Tài chính',
    path: '/finance',
    permission: 'finance.view',
  ),
  (
    tabKey: 'settings',
    icon: Icons.settings_outlined,
    selected: Icons.settings,
    label: 'Cài đặt',
    path: '/settings',
    permission: null,
  ),
];
