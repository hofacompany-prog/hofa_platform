import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/branch.dart';
import '../models/delivery.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../repositories/delivery_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/pickup_repository.dart';
import '../repositories/product_repository.dart';
import 'auth_provider.dart';

const kTerminalDeliveryStatuses = {'delivered', 'failed', 'returned'};

final _deliveryRepo = DeliveryRepository();
final _productRepo = ProductRepository();

/// Danh sách sản phẩm 1 cửa hàng để chọn báo giá sai (report_price_screen.dart).
final merchantProductPickerProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, merchantId) => _productRepo.products(merchantId: merchantId),
    );

/// TẤT CẢ chuyến đang chạy dở (đã gán nhưng chưa xong) cùng lúc — tài xế THƯỜNG chỉ có tối đa 1
/// phần tử, nhưng tài xế thuộc nhóm "Dự phòng" (drivers.is_backup_driver, xem
/// hofa-db/98_backup_driver_pool.sql) có thể có NHIỀU chuyến cùng lúc — sắp theo assignedAt tăng
/// dần (chuyến nhận trước lên đầu). home_screen.dart/offer_screen.dart dùng danh sách này để
/// hiện đủ mọi chuyến thay vì chỉ chuyến đầu tiên như activeDeliveryProvider (giữ lại bên dưới
/// cho các chỗ chỉ cần biết "có đang bận không", không cần liệt kê hết).
final activeDeliveriesProvider = FutureProvider.autoDispose<List<Delivery>>((
  ref,
) async {
  final driver = await ref.watch(myDriverProvider.future);
  if (driver == null) return const [];
  final list = await _deliveryRepo.mine(limit: 20);
  final active = list
      .where((d) => !kTerminalDeliveryStatuses.contains(d.status))
      .toList()
    ..sort((a, b) {
      final aTime = a.assignedAt;
      final bTime = b.assignedAt;
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });
  return active;
});

/// Chuyến đang chạy dở ĐẦU TIÊN (đã gán nhưng chưa xong) — null nếu tài xế đang rảnh. Dùng ở
/// những chỗ chỉ cần 1 chuyến đại diện (vd ghi vệt đường lúc theo dõi vị trí); cần ĐỦ danh sách
/// (tài xế dự phòng có thể nhiều hơn 1) thì dùng activeDeliveriesProvider ở trên.
final activeDeliveryProvider = FutureProvider.autoDispose<Delivery?>((ref) async {
  final list = await ref.watch(activeDeliveriesProvider.future);
  return list.isEmpty ? null : list.first;
});

final deliveryProvider = FutureProvider.autoDispose.family<Delivery, String>((ref, id) => _deliveryRepo.get(id));

/// Đơn (Order) + chi nhánh lấy hàng (Branch) ứng với 1 chuyến — dùng chung cho home_screen.dart
/// (hiện mã đơn ở mỗi thẻ chuyến) và offer_screen.dart (chi tiết điểm lấy/giao lúc xác nhận).
final orderForDeliveryProvider = FutureProvider.autoDispose
    .family<Order, String>((ref, orderId) => OrderRepository().get(orderId));
final branchForDeliveryProvider = FutureProvider.autoDispose
    .family<Branch, String>((ref, branchId) => PickupRepository().branch(branchId));

/// deliveryId của màn nhận đơn đang chờ tài xế quyết định (còn "assigned", chưa nhận/từ chối/
/// hết hạn) — null khi không có màn nào đang mở kiểu này. PopScope(canPop: false) ở
/// OfferScreen chỉ chặn được pop kiểu Flutter Navigator (nút back trong app, Android predictive
/// back đôi khi), KHÔNG chặn được nút back của trình duyệt trên web (đã xác nhận qua thực tế:
/// bấm back vẫn thoát ra ngoài được) — router.dart đọc biến này ở redirect để tự đẩy trở lại
/// /offer/:id bất kể người dùng thoát ra bằng cách nào, cho tới khi màn đó tự xoá biến (xem
/// OfferScreen._setPendingOffer/_clearPendingOffer).
final pendingOfferIdProvider = StateProvider<String?>((ref) => null);
