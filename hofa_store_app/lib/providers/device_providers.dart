import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/device_repository.dart';

final deviceRepoProvider = Provider((ref) => DeviceRepository());

final devicesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(deviceRepoProvider).list(),
);

/// Mã máy cục bộ của thiết bị đang mở app — so với UserDevice.deviceId để đánh dấu
/// "Thiết bị này" trong danh sách.
final currentDeviceIdProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(deviceRepoProvider).currentDeviceId(),
);
