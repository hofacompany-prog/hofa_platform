import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/badge_service.dart';
import '../models/app_notification.dart';
import '../repositories/notification_repository.dart';

/// Riêng 1 file (khác cách khai báo provider ngay trong màn hình như các list khác của app
/// này) vì unread count cần dùng chung giữa icon chuông (products_list_screen.dart) và màn
/// hộp thư (notifications_screen.dart) — invalidate ở 1 nơi phải cập nhật được cả 2.
final notificationRepoProvider = Provider((ref) => NotificationRepository());

/// [category] null = tab "Tất cả" — dùng .family để mỗi tab trong màn hộp thư giữ cache
/// riêng, đổi tab không phải chờ tải lại nếu đã xem qua rồi.
final notificationsProvider = FutureProvider.autoDispose
    .family<List<AppNotification>, String?>(
      (ref, category) =>
          ref.watch(notificationRepoProvider).list(category: category),
    );

/// Tổng số chưa đọc MỌI danh mục — hiện ở icon chuông (khác unreadOrderCountProvider, chỉ
/// tính riêng "Đơn hàng", dùng cho badge biểu tượng PWA ở màn hình chính).
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepoProvider).unreadCount(),
);

/// Số thông báo "Đơn hàng" chưa đọc — vừa hiện trong app vừa TỰ ĐỘNG đồng bộ ra badge trên
/// biểu tượng PWA ở màn hình chính (BadgeService, no-op trên mobile/trình duyệt không hỗ
/// trợ). Watch provider này ở đâu (vd DashboardShell) là đủ để badge luôn đúng mỗi khi
/// provider được tải lại — không cần gọi BadgeService riêng ở nơi khác.
final unreadOrderCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final count = await ref
      .watch(notificationRepoProvider)
      .unreadCount(category: 'order');
  BadgeService.set(count);
  return count;
});
