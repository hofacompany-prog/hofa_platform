import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../repositories/notification_repository.dart';

final notificationRepoProvider = Provider((ref) => NotificationRepository());

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepoProvider).list(),
);

/// Số chưa đọc — dùng chung giữa icon chuông (home_screen.dart) và màn hộp thư
/// (notifications_screen.dart), invalidate ở 1 nơi cập nhật được cả 2.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepoProvider).unreadCount(),
);
