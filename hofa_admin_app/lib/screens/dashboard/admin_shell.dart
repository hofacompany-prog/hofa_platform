import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_version_text.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static const _items = [
    (
      icon: Icons.dashboard_outlined,
      selected: Icons.dashboard,
      label: 'Tổng quan',
      path: '/',
    ),
    (
      icon: Icons.storefront_outlined,
      selected: Icons.storefront,
      label: 'Cửa hàng',
      path: '/merchants',
    ),
    (
      icon: Icons.receipt_long_outlined,
      selected: Icons.receipt_long,
      label: 'Đơn hàng',
      path: '/orders',
    ),
    (
      icon: Icons.people_outline,
      selected: Icons.people,
      label: 'Người dùng',
      path: '/users',
    ),
    (
      icon: Icons.two_wheeler_outlined,
      selected: Icons.two_wheeler,
      label: 'Tài xế',
      path: '/drivers',
    ),
    (
      icon: Icons.category_outlined,
      selected: Icons.category,
      label: 'Danh mục',
      path: '/categories',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      selected: Icons.account_balance_wallet,
      label: 'Tài chính',
      path: '/finance',
    ),
    (
      icon: Icons.local_shipping_outlined,
      selected: Icons.local_shipping,
      label: 'Phí ship',
      path: '/shipping-fee',
    ),
    (
      icon: Icons.confirmation_number_outlined,
      selected: Icons.confirmation_number,
      label: 'Voucher',
      path: '/vouchers',
    ),
    (
      icon: Icons.tag_outlined,
      selected: Icons.tag,
      label: 'Mã đơn hàng',
      path: '/order-code',
    ),
    (
      icon: Icons.notifications_outlined,
      selected: Icons.notifications,
      label: 'Thông báo',
      path: '/notifications',
    ),
    (
      icon: Icons.tune_outlined,
      selected: Icons.tune,
      label: 'Thông số',
      path: '/auto-accept-settings',
    ),
  ];

  int _indexFor(String location) {
    // '/' chỉ khớp khi đúng bằng '/', nếu không mọi route đều khớp tiền tố này
    if (location == '/') return 0;
    final i = _items.indexWhere(
      (d) => d.path != '/' && location.startsWith(d.path),
    );
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final wide = MediaQuery.of(context).size.width > 1100;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            minExtendedWidth: 210,
            selectedIndex: _indexFor(location),
            onDestinationSelected: (i) => context.go(_items[i].path),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Image.asset('assets/images/logo.png', height: 30),
                  if (wide) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'HOFA Admin',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wide && profile != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            profile.fullName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Đăng xuất',
                        icon: const Icon(Icons.logout),
                        onPressed: () =>
                            Supabase.instance.client.auth.signOut(),
                      ),
                      if (wide) ...[
                        const SizedBox(height: 4),
                        const AppVersionText(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            destinations: _items
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
