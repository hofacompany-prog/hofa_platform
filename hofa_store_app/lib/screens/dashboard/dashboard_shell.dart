import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/nav_destinations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';

/// Ngưỡng bề rộng chuyển giữa 2 kiểu điều hướng — dưới ngưỡng này (điện thoại/PWA cài trên
/// điện thoại) dùng thanh tab dưới cùng kiểu app di động; từ ngưỡng này trở lên (tablet/máy
/// tính) dùng NavigationRail bên trái như 1 web app quản trị thông thường.
const _kMobileBreakpoint = 700.0;

/// "Trang chủ" chỉ có ở đây (không nằm trong kNavDestinations dùng chung với lưới lối tắt ở
/// HomeScreen, vì lưới đó không cần link tới chính nó).
const _shellDestinations = <NavDestination>[
  (
    icon: Icons.home_outlined,
    selected: Icons.home,
    label: 'Trang chủ',
    path: '/home',
  ),
  ...kNavDestinations,
];

class DashboardShell extends ConsumerWidget {
  final Widget child;
  const DashboardShell({super.key, required this.child});

  int _indexFor(String location) {
    final i = _shellDestinations.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(myMerchantProvider);
    final location = GoRouterState.of(context).matchedLocation;
    // Watch ở đây (widget luôn mounted xuyên suốt app) để badge biểu tượng PWA ở màn hình
    // chính luôn tự đồng bộ đúng số đơn chưa đọc — side effect nằm trong provider, xem
    // notification_providers.dart. Kết quả count cũng tận dụng luôn để hiện badge ngay
    // trên tab "Đơn hàng" của điều hướng chính cho rõ ràng hơn nữa.
    final unreadOrders = ref.watch(unreadOrderCountProvider).valueOrNull ?? 0;
    final selectedIndex = _indexFor(location);
    final isMobile = MediaQuery.of(context).size.width < _kMobileBreakpoint;

    if (isMobile) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => context.go(_shellDestinations[i].path),
          destinations: _shellDestinations
              .map((d) => NavigationDestination(
                    icon: _destinationIcon(d, d.icon, unreadOrders),
                    selectedIcon: _destinationIcon(d, d.selected, unreadOrders),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 900,
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => context.go(_shellDestinations[i].path),
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
                    error: (_, _) => const SizedBox(),
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
            destinations: _shellDestinations
                .map((d) => NavigationRailDestination(
                      icon: _destinationIcon(d, d.icon, unreadOrders),
                      selectedIcon: _destinationIcon(d, d.selected, unreadOrders),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _destinationIcon(NavDestination d, IconData icon, int unreadOrders) {
    final showBadge = d.path == '/orders' && unreadOrders > 0;
    return showBadge ? Badge(label: Text('$unreadOrders'), child: Icon(icon)) : Icon(icon);
  }
}
