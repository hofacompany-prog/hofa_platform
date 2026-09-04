import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/nav_icon_providers.dart';
import '../../providers/notification_providers.dart';
import '../../widgets/tab_icon.dart';

class DriverShell extends ConsumerWidget {
  final Widget child;
  const DriverShell({super.key, required this.child});

  static const _tabs = ['/', '/earnings', '/profile'];
  static const _tabKeys = ['home', 'earnings', 'profile'];
  static const _icons = [Icons.two_wheeler_outlined, Icons.payments_outlined, Icons.person_outline];
  static const _selectedIcons = [Icons.two_wheeler, Icons.payments, Icons.person];
  static const _labels = ['Trang chủ', 'Thu nhập', 'Cá nhân'];

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location == t || (t != '/' && location.startsWith(t)));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    final iconByTabKey = ref.watch(navIconsProvider).valueOrNull ?? const {};
    // Watch ở đây (bọc TOÀN BỘ route) CHỈ để side effect BadgeService.set() (badge icon app)
    // tự đồng bộ đúng số thông báo "Đơn hàng"/chuyến giao chưa đọc — xem notification_
    // providers.dart.
    ref.watch(unreadOrderCountProvider);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: TabIcon(
                url: iconByTabKey[_tabKeys[i]],
                fallback: _icons[i],
                color: theme.colorScheme.outline,
              ),
              selectedIcon: TabIcon(
                url: iconByTabKey[_tabKeys[i]],
                fallback: _selectedIcons[i],
                color: theme.colorScheme.primary,
              ),
              label: _labels[i],
            ),
        ],
      ),
    );
  }
}
