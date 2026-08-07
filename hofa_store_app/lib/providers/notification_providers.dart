import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../repositories/notification_repository.dart';

/// Riêng 1 file (khác cách khai báo provider ngay trong màn hình như các list khác của app
/// này) vì unread count cần dùng chung giữa icon chuông (products_list_screen.dart) và màn
/// hộp thư (notifications_screen.dart) — invalidate ở 1 nơi phải cập nhật được cả 2.
final notificationRepoProvider = Provider((ref) => NotificationRepository());

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepoProvider).list(),
);

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepoProvider).unreadCount(),
);
