import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_exception.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/user_device.dart';
import '../models/merchant.dart';
import '../models/merchant_device.dart';
import '../models/merchant_fee_tier.dart';
import '../models/platform_fee_settings.dart';
import '../models/topping.dart';
import '../models/driver.dart';
import '../models/bank.dart';
import '../models/driver_wallet_request.dart';
import '../models/admin_delivery.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/shipping_fee_settings.dart';
import '../models/delivery_radius_settings.dart';
import '../models/voucher.dart';
import '../models/voucher_amount_tier.dart';
import '../models/order_settings.dart';
import '../models/auto_accept_settings.dart';
import '../models/driver_accept_settings.dart';
import '../models/driver_dispatch_settings.dart';
import '../models/pickup_proximity_settings.dart';
import '../models/bank_account_settings.dart';
import '../models/admin_contact_settings.dart';
import '../models/pwa_reminder_settings.dart';
import '../models/price_report.dart';
import '../models/admin_notification.dart';
import '../models/notification_settings.dart';
import '../models/nav_tab_icon.dart';
import '../models/icon_library.dart';
import '../models/driver_finance_settings.dart';
import '../models/otp_settings.dart';
import '../models/chat_settings.dart';
import '../models/driver_wallet_summary.dart';
import '../models/merchant_wallet_summary.dart';
import '../models/merchant_wallet_request.dart';
import '../models/merchant_classification.dart';
import '../repositories/admin_repository.dart';
import '../repositories/user_repository.dart';

final adminRepoProvider = Provider((ref) => AdminRepository());

// ---- Xác thực ----

final authStateProvider = StreamProvider<AuthState>(
  (ref) => Supabase.instance.client.auth.onAuthStateChange,
);

final currentSessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  return auth?.session ?? Supabase.instance.client.auth.currentSession;
});

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  try {
    return await UserRepository().me();
  } on ApiException catch (e) {
    if (e.code == 'PROFILE_NOT_FOUND') return null;
    rethrow;
  }
});

// ---- Dữ liệu từng màn hình ----

final statsProvider = FutureProvider.autoDispose<AdminStats>(
  (ref) => ref.watch(adminRepoProvider).stats(),
);

final merchantSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final merchantsProvider = FutureProvider.autoDispose<List<Merchant>>((ref) {
  final q = ref.watch(merchantSearchProvider);
  return ref.watch(adminRepoProvider).merchants(q: q);
});

final merchantDetailProvider = FutureProvider.autoDispose
    .family<Merchant, String>(
      (ref, id) => ref.watch(adminRepoProvider).merchantDetail(id),
    );

final merchantFeeTiersProvider = FutureProvider.autoDispose
    .family<List<MerchantFeeTier>, String>(
      (ref, merchantId) =>
          ref.watch(adminRepoProvider).merchantFeeTiers(merchantId),
    );

final merchantToppingGroupsProvider = FutureProvider.autoDispose
    .family<List<ToppingGroup>, String>(
      (ref, merchantId) =>
          ref.watch(adminRepoProvider).merchantToppingGroups(merchantId),
    );

// categoriesProvider (danh mục hệ thống) đã có sẵn phía trên — dùng lại, không định nghĩa lại.

final merchantCategoriesProvider = FutureProvider.autoDispose
    .family<List<MerchantCategory>, String>(
      (ref, merchantId) =>
          ref.watch(adminRepoProvider).merchantCategories(merchantId: merchantId),
    );

final merchantProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, merchantId) =>
          ref.watch(adminRepoProvider).merchantProducts(merchantId),
    );

final productDetailProvider = FutureProvider.autoDispose.family<Product, String>(
  (ref, productId) => ref.watch(adminRepoProvider).product(productId),
);

final merchantDevicesProvider = FutureProvider.autoDispose
    .family<List<MerchantDevice>, String>(
      (ref, merchantId) =>
          ref.watch(adminRepoProvider).merchantDevices(merchantId),
    );

final userRoleFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

final usersProvider = FutureProvider.autoDispose<List<UserProfile>>((ref) {
  final role = ref.watch(userRoleFilterProvider);
  return ref.watch(adminRepoProvider).users(role: role);
});

final userDetailProvider = FutureProvider.autoDispose
    .family<UserDetail, String>(
      (ref, id) => ref.watch(adminRepoProvider).userDetail(id),
    );

final userDevicesProvider = FutureProvider.autoDispose
    .family<List<UserDevice>, String>(
      (ref, userId) => ref.watch(adminRepoProvider).userDevices(userId),
    );

/// Dữ liệu chặn "Xoá vĩnh viễn" 1 người dùng (cửa hàng đang đứng tên, hồ sơ tài xế, đơn hàng đã
/// đặt) — xem user_blocking_records_screen.dart.
final userBlockingRecordsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, userId) => ref.watch(adminRepoProvider).userBlockingRecords(userId),
    );

final driversProvider = FutureProvider.autoDispose<List<Driver>>(
  (ref) => ref.watch(adminRepoProvider).drivers(),
);

final driverDetailProvider = FutureProvider.autoDispose
    .family<Driver, String>(
      (ref, id) => ref.watch(adminRepoProvider).driverDetail(id),
    );

/// Dữ liệu chặn "Xoá tài xế" — xem driver_blocking_records_screen.dart.
final driverBlockingRecordsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(adminRepoProvider).driverBlockingRecords(id),
    );

final orderStatusFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// Khoảng thời gian tuỳ chọn để lọc đơn hàng (YYYY-MM-DD) — ngoại lệ chỉ admin có, cả 2 để
/// null (mặc định) thì xem mọi đơn không giới hạn thời gian, khác app khách/cửa hàng phải luôn
/// chọn 1 trong 4 khoảng nhanh (Hôm nay/Hôm qua/Tuần qua/Tháng qua).
final orderFromDateProvider = StateProvider.autoDispose<String?>((ref) => null);
final orderToDateProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Chip lọc nhanh "Mua hộ cần tài xế" — bật thì bỏ qua statusFilter (server tự lọc đúng
/// status='ready_for_pickup' + buy_on_behalf + chưa có tài xế), xem orders_screen.dart.
final orderNeedsDriverFilterProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

final ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final needsDriver = ref.watch(orderNeedsDriverFilterProvider);
  final status = ref.watch(orderStatusFilterProvider);
  final from = ref.watch(orderFromDateProvider);
  final to = ref.watch(orderToDateProvider);
  return ref
      .watch(adminRepoProvider)
      .orders(
        status: needsDriver ? null : status,
        from: from,
        to: to,
        needsDriver: needsDriver,
      );
});

final orderDetailProvider = FutureProvider.autoDispose.family<Order, String>(
  (ref, id) => ref.watch(adminRepoProvider).order(id),
);

/// Dữ liệu 4 bảng có thể chặn xoá 1 đơn — xem order_blocking_records_screen.dart.
final orderBlockingRecordsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, orderId) =>
          ref.watch(adminRepoProvider).orderBlockingRecords(orderId),
    );

/// null = đang hoạt động (mặc định phía server), 'all' = mọi trạng thái, hoặc 1 giá trị cụ thể.
final deliveryStatusFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

final deliveriesProvider = FutureProvider.autoDispose<List<AdminDelivery>>((
  ref,
) {
  final status = ref.watch(deliveryStatusFilterProvider);
  return ref.watch(adminRepoProvider).deliveries(status: status);
});

final deliveryDetailProvider = FutureProvider.autoDispose
    .family<AdminDelivery, String>(
      (ref, id) => ref.watch(adminRepoProvider).delivery(id),
    );

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(adminRepoProvider).categories(),
);

final banksProvider = FutureProvider.autoDispose<List<Bank>>(
  (ref) => ref.watch(adminRepoProvider).banks(),
);

final merchantClassificationsProvider =
    FutureProvider.autoDispose<List<MerchantClassification>>(
      (ref) => ref.watch(adminRepoProvider).merchantClassifications(),
    );

final navIconsProvider = FutureProvider.autoDispose<List<NavTabIcon>>(
  (ref) => ref.watch(adminRepoProvider).navIcons(),
);

final iconLibrariesProvider = FutureProvider.autoDispose<List<IconLibrary>>(
  (ref) => ref.watch(adminRepoProvider).iconLibraries(),
);

final pendingWalletDepositsProvider =
    FutureProvider.autoDispose<List<DriverWalletRequest>>(
      (ref) => ref.watch(adminRepoProvider).walletDeposits(status: 'pending'),
    );

final pendingWalletWithdrawalsProvider =
    FutureProvider.autoDispose<List<DriverWalletRequest>>(
      (ref) =>
          ref.watch(adminRepoProvider).walletWithdrawals(status: 'pending'),
    );

final shippingFeeSettingsProvider =
    FutureProvider.autoDispose<ShippingFeeSettings>(
      (ref) => ref.watch(adminRepoProvider).shippingFeeSettings(),
    );

final platformFeeSettingsProvider = FutureProvider.autoDispose<PlatformFeeData>(
  (ref) => ref.watch(adminRepoProvider).platformFeeSettings(),
);

// ---- Ví tài xế ----

final driverWalletSummaryProvider =
    FutureProvider.autoDispose<DriverWalletSummary>(
      (ref) => ref.watch(adminRepoProvider).driverWalletSummary(),
    );

final driverFinanceSettingsProvider =
    FutureProvider.autoDispose<DriverFinanceSettings>(
      (ref) => ref.watch(adminRepoProvider).driverFinanceSettings(),
    );

final otpSettingsProvider = FutureProvider.autoDispose<OtpSettings>(
  (ref) => ref.watch(adminRepoProvider).otpSettings(),
);

final chatSettingsProvider = FutureProvider.autoDispose<ChatSettings>(
  (ref) => ref.watch(adminRepoProvider).chatSettings(),
);

// ---- Ví cửa hàng ----

final merchantWalletSummaryProvider =
    FutureProvider.autoDispose<MerchantWalletSummary>(
      (ref) => ref.watch(adminRepoProvider).merchantWalletSummary(),
    );

final merchantWalletsProvider =
    FutureProvider.autoDispose<List<MerchantWalletBalance>>(
      (ref) => ref.watch(adminRepoProvider).merchantWallets(),
    );

/// null = mọi trạng thái, 'pending' = tab mặc định màn "Cửa hàng rút tiền".
final merchantWithdrawalStatusFilterProvider =
    StateProvider.autoDispose<String?>((ref) => 'pending');

final merchantWalletWithdrawalsProvider =
    FutureProvider.autoDispose<List<MerchantWalletRequest>>((ref) {
      final status = ref.watch(merchantWithdrawalStatusFilterProvider);
      return ref
          .watch(adminRepoProvider)
          .merchantWalletWithdrawals(status: status);
    });

final deliveryRadiusSettingsProvider =
    FutureProvider.autoDispose<DeliveryRadiusSettings>(
      (ref) => ref.watch(adminRepoProvider).deliveryRadiusSettings(),
    );

final vouchersProvider = FutureProvider.autoDispose<List<Voucher>>(
  (ref) => ref.watch(adminRepoProvider).vouchers(),
);

final voucherMaxCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(adminRepoProvider).voucherMaxCount(),
);

final voucherAmountTiersProvider = FutureProvider.autoDispose
    .family<List<VoucherAmountTier>, String>(
      (ref, voucherId) =>
          ref.watch(adminRepoProvider).voucherAmountTiers(voucherId),
    );

final orderSettingsProvider = FutureProvider.autoDispose<OrderSettings>(
  (ref) => ref.watch(adminRepoProvider).orderSettings(),
);

final autoAcceptSettingsProvider =
    FutureProvider.autoDispose<AutoAcceptSettings>(
      (ref) => ref.watch(adminRepoProvider).autoAcceptSettings(),
    );

final driverAcceptSettingsProvider =
    FutureProvider.autoDispose<DriverAcceptSettings>(
      (ref) => ref.watch(adminRepoProvider).driverAcceptSettings(),
    );

final driverDispatchSettingsProvider =
    FutureProvider.autoDispose<DriverDispatchSettings>(
      (ref) => ref.watch(adminRepoProvider).driverDispatchSettings(),
    );

final pickupProximitySettingsProvider =
    FutureProvider.autoDispose<PickupProximitySettings>(
      (ref) => ref.watch(adminRepoProvider).pickupProximitySettings(),
    );

final bankAccountSettingsProvider =
    FutureProvider.autoDispose<BankAccountSettings>(
      (ref) => ref.watch(adminRepoProvider).bankAccountSettings(),
    );

final adminContactSettingsProvider =
    FutureProvider.autoDispose<AdminContactSettings>(
      (ref) => ref.watch(adminRepoProvider).adminContactSettings(),
    );

final pwaReminderSettingsProvider =
    FutureProvider.autoDispose<PwaReminderSettings>(
      (ref) => ref.watch(adminRepoProvider).pwaReminderSettings(),
    );

final pendingPriceReportsProvider = FutureProvider.autoDispose<List<PriceReport>>(
  (ref) => ref.watch(adminRepoProvider).priceReports(status: 'pending'),
);

final pendingPaymentOrdersProvider = FutureProvider.autoDispose<List<Order>>(
  (ref) => ref.watch(adminRepoProvider).orders(status: 'pending_payment'),
);

final notificationsProvider =
    FutureProvider.autoDispose<List<AdminNotification>>(
      (ref) => ref.watch(adminRepoProvider).notifications(),
    );

// Hộp thư theo phạm vi đối tượng (audience_type + chọn cụ thể/tất cả) không dùng provider —
// lựa chọn quá phức tạp để làm key cho .family gọn gàng, _InboxTab tự fetch + setState cục
// bộ (giống _UserPickerDialog/_MerchantPickerDialog cùng file screens/notifications).

final notificationSettingsProvider =
    FutureProvider.autoDispose<NotificationSettings>(
      (ref) => ref.watch(adminRepoProvider).notificationSettings(),
    );
