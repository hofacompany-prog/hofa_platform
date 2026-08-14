import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../repositories/notification_repository.dart';

/// Hộp thư CỦA CHÍNH ADMIN — đơn cần xác nhận thanh toán, tài xế/cửa hàng yêu cầu nạp/rút ví
/// (xem server/src/push.js#notifyAdmins). Riêng 1 file vì unread count cần dùng chung giữa
/// icon chuông (admin_shell.dart) và màn hộp thư (notifications screen), invalidate ở 1 nơi
/// phải cập nhật được cả 2.
final notificationRepoProvider = Provider((ref) => NotificationRepository());

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepoProvider).list(),
);

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepoProvider).unreadCount(),
);
