import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';
import '../providers/notification_providers.dart';
import '../repositories/device_repository.dart';

/// Nhận FCM push khi có việc cần admin xử lý (đơn cần xác nhận thanh toán, tài xế/cửa hàng
/// yêu cầu nạp/rút ví — xem server/src/push.js#notifyAdmins) và điều hướng thẳng tới màn
/// tương ứng. Chỉ web (admin.hofa.com.vn không có bản mobile) — khác push_service.dart của
/// 3 app kia, KHÔNG cần flutter_local_notifications (trình duyệt tự lo lúc app đang mở) hay
/// cơ chế "pending deep link" qua IndexedDB (dành riêng cho PWA/WebAPK Android bị tắt hẳn rồi
/// mở lại từ thông báo — ít xảy ra với 1 trang quản trị chủ yếu mở sẵn trên máy tính).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _registerTokenIfLoggedIn();
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => _registerTokenIfLoggedIn(),
    );
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => _registerTokenIfLoggedIn(),
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => handleData(m.data));

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    // init() được gọi và await TRƯỚC runApp() (xem main.dart) — Navigator chưa tồn tại lúc
    // này, điều hướng ngay sẽ bị handleData() âm thầm bỏ qua (context == null). Đợi 1 khung
    // hình đầu tiên vẽ xong (luôn sau runApp) rồi mới điều hướng.
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => handleData(initial.data),
      );
    }
  }

  Future<void> _registerTokenIfLoggedIn() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: Env.firebaseVapidKey,
      );
      if (token != null) await DeviceRepository().registerPushToken(token);
    } catch (e) {
      debugPrint('[push] Không đăng ký được push token: $e');
    }
  }

  /// Tab admin đang mở sẵn (focus) — service worker KHÔNG chạy onBackgroundMessage lúc này
  /// (chỉ trình duyệt không focus/đóng tab mới vậy), nên phải tự báo bằng SnackBar + làm mới
  /// ngay số chưa đọc ở chuông (invalidate provider) thay vì chờ lần rebuild kế tiếp.
  void _onForegroundMessage(RemoteMessage message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body != null ? '$title — $body' : '$title'),
          action: SnackBarAction(
            label: 'Xem',
            onPressed: () => handleData(message.data),
          ),
        ),
      );
    }
    try {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).invalidate(unreadNotificationCountProvider);
    } catch (_) {}
  }

  void handleData(Map<String, dynamic> data) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    if (data['type'] == 'admin_alert') {
      final screen = data['screen'] as String?;
      if (screen != null && screen.isNotEmpty) context.go(screen);
    }
  }
}
