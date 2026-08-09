import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/tab_icon.dart';

class CustomerShell extends ConsumerWidget {
  final Widget child;
  const CustomerShell({super.key, required this.child});

  static const _items = [
    (
      tabKey: 'home',
      icon: Icons.storefront_outlined,
      selected: Icons.storefront,
      label: 'Trang chủ',
      path: '/',
    ),
    (
      tabKey: 'cart',
      icon: Icons.shopping_cart_outlined,
      selected: Icons.shopping_cart,
      label: 'Giỏ hàng',
      path: '/cart',
    ),
    (
      tabKey: 'preorder',
      icon: Icons.event_repeat_outlined,
      selected: Icons.event_repeat,
      label: 'Đặt trước',
      path: '/preorder',
    ),
    (
      tabKey: 'orders',
      icon: Icons.receipt_long_outlined,
      selected: Icons.receipt_long,
      label: 'Đơn hàng',
      path: '/orders',
    ),
    (
      tabKey: 'profile',
      icon: Icons.person_outline,
      selected: Icons.person,
      label: 'Tài khoản',
      path: '/profile',
    ),
  ];

  int _indexFor(String location) {
    if (location == '/') return 0;
    if (location.startsWith('/merchants') || location.startsWith('/products'))
      return 0;
    if (location.startsWith('/checkout')) return 1;
    final i = _items.indexWhere(
      (d) => d.path != '/' && location.startsWith(d.path),
    );
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(location);
    final cart = ref.watch(cartProvider);
    final instantCount = cart.salesModel == 'instant' ? cart.itemCount : 0;
    final preorderCount = cart.salesModel == 'scheduled' ? cart.itemCount : 0;
    final iconByTabKey = ref.watch(navIconsProvider).valueOrNull ?? const {};

    return Scaffold(
      body: child,
      // onlyShowSelected: chỉ hiện chữ cho mục đang chọn (giống store app) — 5 mục hiện đủ
      // chữ cùng lúc trên màn hẹp dễ bị dính/chật, ẩn bớt chữ mục chưa chọn cho gọn gàng.
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          // Mặc định Material 3 tô icon đang chọn bằng onSecondaryContainer (không phải màu
          // thương hiệu) — ép rõ xanh lá khi chọn, xám khi chưa chọn, để khớp đúng màu xanh
          // admin nhìn thấy lúc chọn icon custom ở màn Icon tabbar (xem widgets/tab_icon.dart,
          // tự đọc IconTheme.of(context).color).
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => context.go(_items[i].path),
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: _items.map((d) {
            final count = d.label == 'Giỏ hàng'
                ? instantCount
                : d.label == 'Đặt trước'
                ? preorderCount
                : 0;
            final iconUrl = iconByTabKey[d.tabKey];
            return NavigationDestination(
              icon: count > 0
                  ? Badge(label: Text('$count'), child: TabIcon(url: iconUrl, fallback: d.icon, size: 22))
                  : TabIcon(url: iconUrl, fallback: d.icon, size: 22),
              selectedIcon: count > 0
                  ? Badge(label: Text('$count'), child: TabIcon(url: iconUrl, fallback: d.selected, size: 22))
                  : TabIcon(url: iconUrl, fallback: d.selected, size: 22),
              label: d.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}
