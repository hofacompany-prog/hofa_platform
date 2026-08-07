import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';

class DashboardShell extends ConsumerWidget {
  final Widget child;
  const DashboardShell({super.key, required this.child});

  static const _destinations = [
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

  int _indexFor(String location) {
    final i = _destinations.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(myMerchantProvider);
    final location = GoRouterState.of(context).matchedLocation;
    // Watch ở đây (widget luôn mounted xuyên suốt app) để badge biểu tượng PWA ở màn hình
    // chính luôn tự đồng bộ đúng số đơn chưa đọc — side effect nằm trong provider, xem
    // notification_providers.dart. Kết quả count cũng tận dụng luôn để hiện badge ngay
    // trên tab "Đơn hàng" của NavigationRail cho rõ ràng hơn nữa.
    final unreadOrders = ref.watch(unreadOrderCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 900,
            selectedIndex: _indexFor(location),
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Image.asset('assets/images/logo.png', height: 32),
                  const SizedBox(height: 8),
                  merchantAsync.when(
                    data: (m) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        m?.name ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Đăng xuất',
                    icon: const Icon(Icons.logout),
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                  ),
                ),
              ),
            ),
            destinations: _destinations
                .map(
                  (d) {
                    final showBadge = d.path == '/orders' && unreadOrders > 0;
                    return NavigationRailDestination(
                      icon: showBadge
                          ? Badge(label: Text('$unreadOrders'), child: Icon(d.icon))
                          : Icon(d.icon),
                      selectedIcon: showBadge
                          ? Badge(label: Text('$unreadOrders'), child: Icon(d.selected))
                          : Icon(d.selected),
                      label: Text(d.label),
                    );
                  },
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
