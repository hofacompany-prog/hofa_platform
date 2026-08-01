import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DriverShell extends StatelessWidget {
  final Widget child;
  const DriverShell({super.key, required this.child});

  static const _tabs = ['/', '/earnings', '/profile'];

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location == t || (t != '/' && location.startsWith(t)));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.two_wheeler_outlined), selectedIcon: Icon(Icons.two_wheeler), label: 'Trang chủ'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Thu nhập'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}
