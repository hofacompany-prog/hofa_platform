import 'package:flutter/material.dart';

/// 1 vị trí tab điều hướng của 1 trong 4 app — [tabKey] khớp với tab_key lưu ở
/// nav_tab_icons (ổn định, không đổi theo route path), [icon]/[selectedIcon] là icon Material
/// mặc định hiện có trong code của app đó (dùng làm fallback khi chưa có icon tuỳ chỉnh, và để
/// hiện preview "mặc định" ở màn Icon tabbar này).
typedef NavTabSlot = ({
  String tabKey,
  String label,
  IconData icon,
  IconData selectedIcon,
});

const Map<String, String> navAppLabels = {
  'admin': 'Admin',
  'customer': 'Khách hàng',
  'store': 'Cửa hàng',
  'driver': 'Tài xế',
};

/// Toàn bộ tab điều hướng của cả 4 app — chép lại đúng danh sách destination hiện có trong
/// từng shell (admin_shell.dart, customer_shell.dart, dashboard_shell.dart, driver_shell.dart).
/// Sửa icon mặc định ở đây KHÔNG tự đổi icon thật trong app đó — đây chỉ là bản ghi để màn Icon
/// tabbar biết có những tab nào mà chọn icon tuỳ chỉnh, app vẫn tự giữ icon mặc định riêng.
const Map<String, List<NavTabSlot>> navTabSlots = {
  'admin': [
    (tabKey: 'dashboard', label: 'Tổng quan', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
    (tabKey: 'merchants', label: 'Cửa hàng', icon: Icons.storefront_outlined, selectedIcon: Icons.storefront),
    (tabKey: 'orders', label: 'Đơn hàng', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
    (tabKey: 'users', label: 'Người dùng', icon: Icons.people_outline, selectedIcon: Icons.people),
    (tabKey: 'drivers', label: 'Tài xế', icon: Icons.two_wheeler_outlined, selectedIcon: Icons.two_wheeler),
    (tabKey: 'categories', label: 'Danh mục', icon: Icons.category_outlined, selectedIcon: Icons.category),
    (tabKey: 'finance', label: 'Tài chính', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
    (tabKey: 'notifications', label: 'Thông báo', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications),
  ],
  'customer': [
    (tabKey: 'home', label: 'Trang chủ', icon: Icons.storefront_outlined, selectedIcon: Icons.storefront),
    (tabKey: 'cart', label: 'Giỏ hàng', icon: Icons.shopping_cart_outlined, selectedIcon: Icons.shopping_cart),
    (tabKey: 'preorder', label: 'Đặt trước', icon: Icons.event_repeat_outlined, selectedIcon: Icons.event_repeat),
    (tabKey: 'orders', label: 'Đơn hàng', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
    (tabKey: 'profile', label: 'Tài khoản', icon: Icons.person_outline, selectedIcon: Icons.person),
  ],
  'store': [
    (tabKey: 'home', label: 'Trang chủ', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (tabKey: 'products', label: 'Sản phẩm', icon: Icons.storefront_outlined, selectedIcon: Icons.storefront),
    (tabKey: 'orders', label: 'Đơn hàng', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
    (tabKey: 'finance', label: 'Tài chính', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
    (tabKey: 'settings', label: 'Cài đặt', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  ],
  'driver': [
    (tabKey: 'home', label: 'Trang chủ', icon: Icons.two_wheeler_outlined, selectedIcon: Icons.two_wheeler),
    (tabKey: 'earnings', label: 'Thu nhập', icon: Icons.payments_outlined, selectedIcon: Icons.payments),
    (tabKey: 'profile', label: 'Cá nhân', icon: Icons.person_outline, selectedIcon: Icons.person),
  ],
};
