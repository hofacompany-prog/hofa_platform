import 'package:flutter/material.dart';
import 'merchants_screen.dart';
import '../settings/order_code_screen.dart';
import '../settings/auto_accept_settings_screen.dart';
import '../settings/delivery_radius_settings_screen.dart';

/// Gom các mục trước đây tách riêng ở NavigationRail (Cửa hàng, Mã đơn hàng, Thông số cửa hàng,
/// Bán kính giao hàng) vào 1 mục "Cửa hàng" duy nhất, mỗi màn là 1 tab con — giữ nguyên hoàn
/// toàn từng màn, chỉ thêm 1 dải tab mỏng phía trên để chuyển qua lại (cùng pattern với
/// DriverHubScreen).
class MerchantHubScreen extends StatelessWidget {
  final int initialTab;
  const MerchantHubScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab.clamp(0, 3),
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: const TabBar(
                // Nhãn dài ("Thông số cửa hàng") dễ bị bóp/xuống dòng nếu chia đều cho cả các
                // tab trên màn hẹp — isScrollable để mỗi tab tự chiếm đúng bề rộng cần, cuộn ngang.
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Cửa hàng'),
                  Tab(text: 'Mã đơn hàng'),
                  Tab(text: 'Thông số cửa hàng'),
                  Tab(text: 'Bán kính giao hàng'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  MerchantsScreen(),
                  OrderCodeScreen(),
                  AutoAcceptSettingsScreen(),
                  DeliveryRadiusSettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
