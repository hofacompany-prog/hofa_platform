import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/badge_service.dart';
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

/// Số thông báo "Đơn hàng"/chuyến giao chưa đọc — vừa hiện trong app vừa TỰ ĐỘNG đồng bộ ra
/// badge icon app (BadgeService — native Android/iOS qua app_badge_plus, web qua Badging API).
/// Watch provider này ở đâu (vd DriverShell) là đủ để badge luôn đúng mỗi khi provider được
/// tải lại — không cần gọi BadgeService riêng ở nơi khác.
final unreadOrderCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final count = await ref
      .watch(notificationRepoProvider)
      .unreadCount(category: 'order');
  BadgeService.set(count);
  return count;
});
