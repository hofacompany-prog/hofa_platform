import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/cart_provider.dart';

class CustomerShell extends ConsumerWidget {
  final Widget child;
  const CustomerShell({super.key, required this.child});

  static const _items = [
    (icon: Icons.storefront_outlined, selected: Icons.storefront, label: 'Trang chủ', path: '/'),
    (icon: Icons.shopping_cart_outlined, selected: Icons.shopping_cart, label: 'Giỏ hàng', path: '/cart'),
    (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Đơn hàng', path: '/orders'),
    (icon: Icons.person_outline, selected: Icons.person, label: 'Tài khoản', path: '/profile'),
  ];

  int _indexFor(String location) {
    if (location == '/') return 0;
    if (location.startsWith('/merchants') || location.startsWith('/products')) return 0;
    if (location.startsWith('/checkout')) return 1;
    final i = _items.indexWhere((d) => d.path != '/' && location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(location);
    final cartCount = ref.watch(cartProvider.select((c) => c.itemCount));

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => context.go(_items[i].path),
        destinations: _items
            .map((d) => NavigationDestination(
                  icon: d.label == 'Giỏ hàng' && cartCount > 0
                      ? Badge(label: Text('$cartCount'), child: Icon(d.icon))
                      : Icon(d.icon),
                  selectedIcon: d.label == 'Giỏ hàng' && cartCount > 0
                      ? Badge(label: Text('$cartCount'), child: Icon(d.selected))
                      : Icon(d.selected),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}
