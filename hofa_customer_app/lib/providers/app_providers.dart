import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/address.dart';
import '../models/branch.dart';
import '../models/category.dart';
import '../models/delivery.dart';
import '../models/merchant.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/wholesale_tier.dart';
import '../repositories/merchant_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/review_repository.dart';
import '../repositories/voucher_repository.dart';
import 'auth_providers.dart';

final merchantRepoProvider = Provider((ref) => MerchantRepository());
final productRepoProvider = Provider((ref) => ProductRepository());
final orderRepoProvider = Provider((ref) => OrderRepository());
final voucherRepoProvider = Provider((ref) => VoucherRepository());
final reviewRepoProvider = Provider((ref) => ReviewRepository());

// ---- Cửa hàng ----

final merchantSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final merchantsProvider = FutureProvider.autoDispose<List<Merchant>>((ref) {
  final q = ref.watch(merchantSearchProvider);
  return ref.watch(merchantRepoProvider).merchants(q: q);
});

final merchantDetailProvider =
    FutureProvider.autoDispose.family<Merchant, String>((ref, id) => ref.watch(merchantRepoProvider).merchant(id));

final merchantBranchesProvider =
    FutureProvider.autoDispose.family<List<Branch>, String>((ref, merchantId) => ref.watch(merchantRepoProvider).branches(merchantId));

// ---- Sản phẩm ----

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(productRepoProvider).categories());

final merchantProductsProvider =
    FutureProvider.autoDispose.family<List<Product>, String>((ref, merchantId) => ref.watch(productRepoProvider).products(merchantId: merchantId));

final productDetailProvider =
    FutureProvider.autoDispose.family<Product, String>((ref, id) => ref.watch(productRepoProvider).product(id));

final wholesaleTiersProvider = FutureProvider.autoDispose.family<List<WholesaleTier>, String>(
    (ref, variantId) => ref.watch(productRepoProvider).wholesaleTiers(variantId));

// ---- Đơn hàng ----

final orderStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final myOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final status = ref.watch(orderStatusFilterProvider);
  return ref.watch(orderRepoProvider).myOrders(status: status);
});

final orderDetailProvider =
    FutureProvider.autoDispose.family<Order, String>((ref, id) => ref.watch(orderRepoProvider).order(id));

final orderHistoryProvider =
    FutureProvider.autoDispose.family<List<OrderStatusEvent>, String>((ref, id) => ref.watch(orderRepoProvider).history(id));

final orderDeliveryProvider =
    FutureProvider.autoDispose.family<Delivery?, String>((ref, id) => ref.watch(orderRepoProvider).delivery(id));

// ---- Địa chỉ ----

final addressesProvider = FutureProvider.autoDispose<List<Address>>((ref) => ref.watch(userRepoProvider).addresses());

// ---- Đánh giá ----

final productReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
    (ref, productId) => ref.watch(reviewRepoProvider).list(targetType: 'product', targetId: productId));
