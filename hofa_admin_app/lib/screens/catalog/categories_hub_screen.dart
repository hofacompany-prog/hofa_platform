import 'package:flutter/material.dart';
import 'categories_screen.dart';
import '../settings/nav_icons_screen.dart';

/// Gộp "Danh mục ngành hàng" và "Icon tabbar" (chọn icon Lucide cho cả 4 app) vào 1 mục
/// "Danh mục" duy nhất trên NavigationRail — cùng pattern với MerchantHubScreen/DriverHubScreen.
/// Icon tabbar đặt cạnh danh mục vì cùng là nơi quản lý icon, tránh mọc thêm mục rail mới.
class CategoriesHubScreen extends StatelessWidget {
  final int initialTab;
  const CategoriesHubScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: const TabBar(
                tabs: [
                  Tab(text: 'Danh mục'),
                  Tab(text: 'Icon tabbar'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  CategoriesScreen(),
                  NavIconsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
