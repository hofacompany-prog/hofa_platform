import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/delivery.dart';
import '../repositories/delivery_repository.dart';
import 'auth_provider.dart';

const kTerminalDeliveryStatuses = {'delivered', 'failed', 'returned'};

final _deliveryRepo = DeliveryRepository();

/// Chuyến đang chạy dở (đã gán nhưng chưa xong) — null nếu tài xế đang rảnh.
final activeDeliveryProvider = FutureProvider.autoDispose<Delivery?>((ref) async {
  final driver = await ref.watch(myDriverProvider.future);
  if (driver == null) return null;
  final list = await _deliveryRepo.mine(limit: 5);
  for (final d in list) {
    if (!kTerminalDeliveryStatuses.contains(d.status)) return d;
  }
  return null;
});

final deliveryProvider = FutureProvider.autoDispose.family<Delivery, String>((ref, id) => _deliveryRepo.get(id));

/// deliveryId của màn nhận đơn đang chờ tài xế quyết định (còn "assigned", chưa nhận/từ chối/
/// hết hạn) — null khi không có màn nào đang mở kiểu này. PopScope(canPop: false) ở
/// OfferScreen chỉ chặn được pop kiểu Flutter Navigator (nút back trong app, Android predictive
/// back đôi khi), KHÔNG chặn được nút back của trình duyệt trên web (đã xác nhận qua thực tế:
/// bấm back vẫn thoát ra ngoài được) — router.dart đọc biến này ở redirect để tự đẩy trở lại
/// /offer/:id bất kể người dùng thoát ra bằng cách nào, cho tới khi màn đó tự xoá biến (xem
/// OfferScreen._setPendingOffer/_clearPendingOffer).
final pendingOfferIdProvider = StateProvider<String?>((ref) => null);
