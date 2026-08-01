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
