import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/address.dart';
import '../models/branch.dart';
import '../models/category.dart';
import '../models/delivery.dart';
import '../models/merchant.dart';
import '../models/merchant_fee_tier.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/shipping_fee_settings.dart';
import '../models/topping.dart';
import '../models/voucher.dart';
import '../models/wholesale_tier.dart';
import '../repositories/merchant_repository.dart';
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

final merchantSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final merchantsProvider = FutureProvider.autoDispose<List<Merchant>>((ref) {
  final q = ref.watch(merchantSearchProvider);
  return ref.watch(merchantRepoProvider).merchants(q: q);
});

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

// ---- Sản phẩm ----

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(productRepoProvider).categories(),
);

final merchantProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, merchantId) =>
          ref.watch(productRepoProvider).products(merchantId: merchantId),
    );

final merchantCategoriesProvider = FutureProvider.autoDispose
    .family<List<MerchantCategory>, String>(
      (ref, merchantId) =>
          ref.watch(productRepoProvider).merchantCategories(merchantId),
    );

final categoryProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, categoryId) =>
          ref.watch(productRepoProvider).products(categoryId: categoryId),
    );

final categoryFeaturedProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, categoryId) => ref
          .watch(productRepoProvider)
          .products(categoryId: categoryId, isFeatured: true, limit: 10),
    );

final productSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final searchedProductsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) {
  final q = ref.watch(productSearchProvider);
  if (q.isEmpty) return Future.value(<Product>[]);
  return ref.watch(productRepoProvider).products(q: q);
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

final myOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final status = ref.watch(orderStatusFilterProvider);
  return ref.watch(orderRepoProvider).myOrders(status: status);
});

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
