import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/admin_providers.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/app_version_text.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/tab_icon.dart';

class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return IconButton(
      tooltip: isDark ? 'Chuyển giao diện sáng' : 'Chuyển giao diện tối',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
    );
  }
}

class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static const _items = [
    (
      tabKey: 'dashboard',
      icon: Icons.dashboard_outlined,
      selected: Icons.dashboard,
      label: 'Tổng quan',
      path: '/',
    ),
    (
      tabKey: 'merchants',
      icon: Icons.storefront_outlined,
      selected: Icons.storefront,
      label: 'Cửa hàng',
      path: '/merchants',
    ),
    (
      tabKey: 'orders',
      icon: Icons.receipt_long_outlined,
      selected: Icons.receipt_long,
      label: 'Đơn hàng',
      path: '/orders',
    ),
    (
      tabKey: 'users',
      icon: Icons.people_outline,
      selected: Icons.people,
      label: 'Người dùng',
      path: '/users',
    ),
    (
      tabKey: 'drivers',
      icon: Icons.two_wheeler_outlined,
      selected: Icons.two_wheeler,
      label: 'Tài xế',
      path: '/drivers',
    ),
    (
      tabKey: 'categories',
      icon: Icons.category_outlined,
      selected: Icons.category,
      label: 'Danh mục',
      path: '/categories',
    ),
    (
      tabKey: 'finance',
      icon: Icons.account_balance_wallet_outlined,
      selected: Icons.account_balance_wallet,
      label: 'Tài chính',
      path: '/finance',
    ),
    (
      tabKey: 'notifications',
      icon: Icons.notifications_outlined,
      selected: Icons.notifications,
      label: 'Thông báo',
      path: '/notifications',
    ),
  ];

  // Dưới ngưỡng này (điện thoại) NavigationRail luôn-hiện-sẵn chiếm mất quá nhiều bề rộng còn
  // lại cho nội dung (8 mục — quá nhiều để nhét vừa 1 thanh tab dưới cùng kiểu app di động,
  // khác các app kia chỉ 5-6 mục) — chuyển sang AppBar + Drawer để nội dung được toàn bộ bề
  // rộng màn hình, khớp cách hofa_store_app/dashboard_shell.dart xử lý ngưỡng tương tự.
  static const _kMobileBreakpoint = 700.0;

  int _indexFor(String location) {
    // '/' chỉ khớp khi đúng bằng '/', nếu không mọi route đều khớp tiền tố này
    if (location == '/') return 0;
    // Chi tiết chuyến giao hàng (/deliveries/:id) nằm trong tab con "Chuyến giao hàng" của mục
    // "Tài xế" (/drivers), không còn là mục riêng ở NavigationRail — vẫn phải highlight đúng.
    if (location.startsWith('/deliveries')) {
      return _items.indexWhere((d) => d.path == '/drivers');
    }
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
    final isMobile = MediaQuery.of(context).size.width < _kMobileBreakpoint;
    // Trước đây chỉ hiện nhãn NavigationRail khi > 1100px (dưới mức đó thu về icon-only) —
    // bỏ hẳn ngưỡng phụ này, hễ đã qua _kMobileBreakpoint (không còn ở chế độ AppBar+Drawer)
    // là hiện nhãn luôn, tránh 1 khoảng rộng giữa chừng (700–1100px) mất chữ khó hiểu.
    final wide = !isMobile;
    final navIcons = ref.watch(navIconsProvider).valueOrNull ?? const [];
    final iconByTabKey = {
      for (final n in navIcons)
        if (n.app == 'admin') n.tabKey: n.iconUrl,
    };
    final selectedIndex = _indexFor(location);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_items[selectedIndex].label),
          actions: const [NotificationBell(), SizedBox(width: 8)],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Image.asset('assets/images/logo.png', height: 30),
                      const SizedBox(height: 8),
                      const Text(
                        'HOFA Admin',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (profile != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            profile.fullName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        ListTile(
                          leading: TabIcon(
                            url: iconByTabKey[_items[i].tabKey],
                            fallback: i == selectedIndex
                                ? _items[i].selected
                                : _items[i].icon,
                            color: i == selectedIndex
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          title: Text(
                            _items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: i == selectedIndex,
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go(_items[i].path);
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Consumer(
                  builder: (context, ref, _) => ListTile(
                    leading: const _ThemeToggleButton(),
                    title: const Text('Giao diện sáng/tối'),
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Đăng xuất'),
                  onTap: () => Supabase.instance.client.auth.signOut(),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: AppVersionText(),
                ),
              ],
            ),
          ),
        ),
        body: child,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            minExtendedWidth: 210,
            selectedIndex: selectedIndex,
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
                      const _ThemeToggleButton(),
                      const NotificationBell(),
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
                    icon: TabIcon(
                      url: iconByTabKey[d.tabKey],
                      fallback: d.icon,
                      color: theme.colorScheme.outline,
                    ),
                    selectedIcon: TabIcon(
                      url: iconByTabKey[d.tabKey],
                      fallback: d.selected,
                      color: theme.colorScheme.primary,
                    ),
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
