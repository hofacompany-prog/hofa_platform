import 'package:flutter/material.dart';
import 'drivers_screen.dart';
import '../deliveries/deliveries_screen.dart';
import '../settings/driver_accept_settings_screen.dart';
import '../finance/driver_wallet_screen.dart';
import '../settings/driver_finance_settings_screen.dart';

/// Gom các màn trước đây tách riêng ở NavigationRail (Tài xế, Chuyến giao hàng, Thông số tài
/// xế, Ví tài xế, Tài chính tài xế) vào 1 mục "Tài xế" duy nhất, mỗi màn là 1 tab con — giữ
/// nguyên hoàn toàn từng màn (kể cả AppBar/action riêng của nó), chỉ thêm 1 dải tab mỏng phía
/// trên để chuyển qua lại.
class DriverHubScreen extends StatelessWidget {
  final int initialTab;
  const DriverHubScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab.clamp(0, 4),
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Tài xế'),
                  Tab(text: 'Chuyến giao hàng'),
                  Tab(text: 'Thông số'),
                  Tab(text: 'Ví tài xế'),
                  Tab(text: 'Tài chính'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  DriversScreen(),
                  DeliveriesScreen(),
                  DriverAcceptSettingsScreen(),
                  DriverWalletScreen(),
                  DriverFinanceSettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
