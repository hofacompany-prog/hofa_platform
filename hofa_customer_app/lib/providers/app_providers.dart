import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/paginated_list_notifier.dart';
import '../models/address.dart';
import '../models/bank_account_settings.dart';
import '../models/branch.dart';
import '../models/category.dart';
import '../models/delivery.dart';
import '../models/app_notification.dart';
import '../models/merchant.dart';
import '../models/merchant_fee_tier.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/shipping_fee_settings.dart';
import '../models/topping.dart';
import '../models/voucher.dart';
import '../models/wholesale_tier.dart';
import '../repositories/bank_settings_repository.dart';
import '../repositories/merchant_repository.dart';
import '../repositories/nav_icon_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/review_repository.dart';
import '../repositories/shipping_repository.dart';
import '../repositories/voucher_repository.dart';
import 'auth_providers.dart';

final merchantRepoProvider = Provider((ref) => MerchantRepository());
final productRepoProvider = Provider((ref) => ProductRepository());
final orderRepoProvider = Provider((ref) => OrderRepository());
final voucherRepoProvider = Provider((ref) => VoucherRepository());
final reviewRepoProvider = Provider((ref) => ReviewRepository());
final shippingRepoProvider = Provider((ref) => ShippingRepository());
final notificationRepoProvider = Provider((ref) => NotificationRepository());
final bankSettingsRepoProvider = Provider((ref) => BankSettingsRepository());
final navIconRepoProvider = Provider((ref) => NavIconRepository());

/// Icon tabbar tuỳ chỉnh — không cần đăng nhập, lỗi mạng tự trả về map rỗng (xem
/// NavIconRepository), không chặn khởi động app.
final navIconsProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(navIconRepoProvider).navIcons(),
);

/// Hộp thư thông báo — tải dần theo trang (xem PaginatedListNotifier), autoDispose để mỗi lần
/// vào lại màn Thông báo đều bắt đầu lại từ trang đầu.
final notificationsPagedProvider = StateNotifierProvider.autoDispose<
    PaginatedListNotifier<AppNotification>, PaginatedState<AppNotification>>(
  (ref) => PaginatedListNotifier<AppNotification>(
    (limit, offset) =>
        ref.read(notificationRepoProvider).list(limit: limit, offset: offset),
  ),
);

/// Số chưa đọc — hiện badge trên icon chuông ở màn chủ.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepoProvider).unreadCount(),
);

/// Voucher công khai cho khách chọn ở màn thanh toán (xem voucher_picker_dialog.dart).
final publicVouchersProvider = FutureProvider.autoDispose
    .family<List<Voucher>, String>(
      (ref, merchantId) =>
          ref.watch(voucherRepoProvider).publicVouchers(merchantId: merchantId),
    );

final voucherMaxCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(voucherRepoProvider).maxVouchersPerOrder(),
);

// ---- Cửa hàng ----

/// Danh sách cửa hàng duyệt ở trang chủ — tải dần theo trang khi khách lướt xuống, không tải
/// hết 1 lần (xem PaginatedListNotifier).
final merchantsPagedProvider = StateNotifierProvider.autoDispose<
    PaginatedListNotifier<Merchant>, PaginatedState<Merchant>>(
  (ref) => PaginatedListNotifier<Merchant>(
    (limit, offset) =>
        ref.read(merchantRepoProvider).merchants(limit: limit, offset: offset),
  ),
);

final merchantDetailProvider = FutureProvider.autoDispose
    .family<Merchant, String>(
      (ref, id) => ref.watch(merchantRepoProvider).merchant(id),
    );

final merchantBranchesProvider = FutureProvider.autoDispose
    .family<List<Branch>, String>(
      (ref, merchantId) => ref.watch(merchantRepoProvider).branches(merchantId),
    );

final branchDetailProvider = FutureProvider.autoDispose.family<Branch, String>(
  (ref, branchId) => ref.watch(merchantRepoProvider).branch(branchId),
);

/// Bảng bậc phí mua hộ — chỉ có ý nghĩa với cửa hàng merchantType == 'buy_on_behalf'.
final merchantFeeTiersProvider = FutureProvider.autoDispose
    .family<List<MerchantFeeTier>, String>(
      (ref, merchantId) => ref.watch(merchantRepoProvider).feeTiers(merchantId),
    );

/// Cấu hình phí ship toàn sàn (chỉnh ở app admin) — dùng để ước tính phí ship ở giỏ hàng.
final shippingFeeSettingsProvider =
    FutureProvider.autoDispose<ShippingFeeSettings?>(
      (ref) => ref.watch(shippingRepoProvider).feeSettings(),
    );

/// Thông tin tài khoản ngân hàng toàn sàn (chỉnh ở app admin) — dùng dựng QR VietQR ở màn chi
/// tiết đơn cho đơn thanh toán chuyển khoản.
final bankAccountSettingsProvider = FutureProvider.autoDispose<BankAccountSettings>(
  (ref) => ref.watch(bankSettingsRepoProvider).get(),
);

// ---- Sản phẩm ----

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(productRepoProvider).categories(),
);

/// Sản phẩm của 1 cửa hàng — tải dần theo trang.
final merchantProductsPagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<Product>, PaginatedState<Product>, String>(
      (ref, merchantId) => PaginatedListNotifier<Product>(
        (limit, offset) => ref
            .read(productRepoProvider)
            .products(merchantId: merchantId, limit: limit, offset: offset),
      ),
    );

final merchantCategoriesProvider = FutureProvider.autoDispose
    .family<List<MerchantCategory>, String>(
      (ref, merchantId) =>
          ref.watch(productRepoProvider).merchantCategories(merchantId),
    );

/// Sản phẩm thuộc 1 danh mục — categoryId là danh mục CHA thì server tự gộp cả sản phẩm của
/// danh mục con (xem server/src/routes/products.js), là danh mục con thì lọc đúng con đó. Tải
/// dần theo trang — dùng chung cho CategoryProductsScreen (danh mục con) lẫn
/// CategoryDetailScreen (danh mục cha, hiện ngay dưới lưới danh mục con).
final categoryProductsPagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<Product>, PaginatedState<Product>, String>(
      (ref, categoryId) => PaginatedListNotifier<Product>(
        (limit, offset) => ref
            .read(productRepoProvider)
            .products(categoryId: categoryId, limit: limit, offset: offset),
      ),
    );

final productSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final searchedProductsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) {
  final q = ref.watch(productSearchProvider);
  if (q.isEmpty) return Future.value(<Product>[]);
  return ref.watch(productRepoProvider).products(q: q);
});

/// Dùng CHUNG ô tìm kiếm/state với searchedProductsProvider (productSearchProvider) — khách
/// gõ 1 lần ra cả cửa hàng khớp tên lẫn sản phẩm khớp tên/thuộc cửa hàng đó, không cần 2 ô
/// tìm kiếm riêng. Không lọc has_open_branch — tìm kiếm chủ động thì vẫn phải ra cả cửa hàng
/// đang tạm đóng (MerchantCard tự xám nó), khác với danh sách duyệt mặc định ở trang chủ.
final searchedMerchantsProvider = FutureProvider.autoDispose<List<Merchant>>((
  ref,
) {
  final q = ref.watch(productSearchProvider);
  if (q.isEmpty) return Future.value(<Merchant>[]);
  return ref.watch(merchantRepoProvider).merchants(q: q);
});

final productDetailProvider = FutureProvider.autoDispose
    .family<Product, String>(
      (ref, id) => ref.watch(productRepoProvider).product(id),
    );

final wholesaleTiersProvider = FutureProvider.autoDispose
    .family<List<WholesaleTier>, String>(
      (ref, variantId) =>
          ref.watch(productRepoProvider).wholesaleTiers(variantId),
    );

final toppingGroupsProvider = FutureProvider.autoDispose
    .family<List<ToppingGroup>, String>(
      (ref, productId) =>
          ref.watch(productRepoProvider).toppingGroups(productId),
    );

// ---- Đơn hàng ----

final orderStatusFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// Đơn hàng của khách — tải dần theo trang. family theo status: đổi bộ lọc trạng thái tự tạo
/// notifier mới nên tự reset về trang đầu, không cần code riêng.
final myOrdersPagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<Order>, PaginatedState<Order>, String?>(
      (ref, status) => PaginatedListNotifier<Order>(
        (limit, offset) => ref
            .read(orderRepoProvider)
            .myOrders(status: status, limit: limit, offset: offset),
      ),
    );

final orderDetailProvider = FutureProvider.autoDispose.family<Order, String>(
  (ref, id) => ref.watch(orderRepoProvider).order(id),
);

final orderHistoryProvider = FutureProvider.autoDispose
    .family<List<OrderStatusEvent>, String>(
      (ref, id) => ref.watch(orderRepoProvider).history(id),
    );

final orderDeliveryProvider = FutureProvider.autoDispose
    .family<Delivery?, String>(
      (ref, id) => ref.watch(orderRepoProvider).delivery(id),
    );

// ---- Địa chỉ ----

final addressesProvider = FutureProvider.autoDispose<List<Address>>(
  (ref) => ref.watch(userRepoProvider).addresses(),
);

// ---- Đánh giá ----

final productReviewsProvider = FutureProvider.autoDispose
    .family<List<Review>, String>(
      (ref, productId) => ref
          .watch(reviewRepoProvider)
          .list(targetType: 'product', targetId: productId),
    );

/// Đánh giá cửa hàng — key gồm rating lọc (null = tất cả) để đổi bộ lọc tự tạo trang mới,
/// khớp cách merchantProductsPagedProvider dùng family cho mỗi merchantId.
final merchantReviewsPagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<Review>, PaginatedState<Review>, (String, int?)>(
      (ref, key) => PaginatedListNotifier<Review>(
        (limit, offset) => ref.read(reviewRepoProvider).list(
              targetType: 'merchant',
              targetId: key.$1,
              rating: key.$2,
              limit: limit,
              offset: offset,
            ),
      ),
    );

/// Mọi đánh giá (mọi target_type) của 1 đơn — màn chi tiết đơn dùng để biết đã đánh giá
/// món/cửa hàng/tài xế nào rồi.
final orderReviewsProvider = FutureProvider.autoDispose
    .family<List<Review>, String>(
      (ref, orderId) => ref.watch(reviewRepoProvider).listByOrder(orderId),
    );
