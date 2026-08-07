import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_exception.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/merchant.dart';
import '../models/merchant_device.dart';
import '../models/merchant_fee_tier.dart';
import '../models/driver.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/shipping_fee_settings.dart';
import '../models/voucher.dart';
import '../models/order_settings.dart';
import '../models/auto_accept_settings.dart';
import '../models/admin_notification.dart';
import '../models/notification_settings.dart';
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

final driversProvider = FutureProvider.autoDispose<List<Driver>>(
  (ref) => ref.watch(adminRepoProvider).drivers(),
);

final orderStatusFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

final ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final status = ref.watch(orderStatusFilterProvider);
  return ref.watch(adminRepoProvider).orders(status: status);
});

final orderDetailProvider = FutureProvider.autoDispose.family<Order, String>(
  (ref, id) => ref.watch(adminRepoProvider).order(id),
);

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(adminRepoProvider).categories(),
);

final shippingFeeSettingsProvider =
    FutureProvider.autoDispose<ShippingFeeSettings>(
      (ref) => ref.watch(adminRepoProvider).shippingFeeSettings(),
    );

final vouchersProvider = FutureProvider.autoDispose<List<Voucher>>(
  (ref) => ref.watch(adminRepoProvider).vouchers(),
);

final voucherMaxCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(adminRepoProvider).voucherMaxCount(),
);

final orderSettingsProvider = FutureProvider.autoDispose<OrderSettings>(
  (ref) => ref.watch(adminRepoProvider).orderSettings(),
);

final autoAcceptSettingsProvider = FutureProvider.autoDispose<AutoAcceptSettings>(
  (ref) => ref.watch(adminRepoProvider).autoAcceptSettings(),
);

final notificationsProvider =
    FutureProvider.autoDispose<List<AdminNotification>>(
      (ref) => ref.watch(adminRepoProvider).notifications(),
    );

// Hộp thư theo phạm vi đối tượng (audience_type + chọn cụ thể/tất cả) không dùng provider —
// lựa chọn quá phức tạp để làm key cho .family gọn gàng, _InboxTab tự fetch + setState cục
// bộ (giống _UserPickerDialog/_MerchantPickerDialog cùng file screens/notifications).

final notificationSettingsProvider = FutureProvider.autoDispose<NotificationSettings>(
  (ref) => ref.watch(adminRepoProvider).notificationSettings(),
);
