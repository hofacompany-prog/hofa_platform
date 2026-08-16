import 'package:flutter/material.dart';
import 'finance_settings_screen.dart';
import 'shipping_fee_screen.dart';
import 'platform_fee_screen.dart';
import 'payment_settings_screen.dart';
import '../vouchers/vouchers_screen.dart';

/// Gom các mục trước đây tách riêng ở NavigationRail (Tài chính, Phí ship, Phí mua hộ,
/// Voucher, Thanh toán) vào 1 mục "Tài chính" duy nhất, mỗi màn là 1 tab con — giữ nguyên
/// hoàn toàn từng màn (kể cả PaymentSettingsScreen tự có 5 tab con riêng bên trong), chỉ
/// thêm 1 dải tab mỏng phía trên để chuyển qua lại (cùng pattern với
/// DriverHubScreen/MerchantHubScreen).
class FinanceHubScreen extends StatelessWidget {
  final int initialTab;
  const FinanceHubScreen({super.key, this.initialTab = 0});

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
                  Tab(text: 'Tài chính'),
                  Tab(text: 'Phí ship'),
                  Tab(text: 'Phí mua hộ'),
                  Tab(text: 'Voucher'),
                  Tab(text: 'Thanh toán'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  FinanceSettingsScreen(),
                  ShippingFeeScreen(),
                  PlatformFeeScreen(),
                  VouchersScreen(),
                  PaymentSettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
