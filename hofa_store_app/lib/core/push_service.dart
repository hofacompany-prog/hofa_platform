import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';
import '../repositories/device_repository.dart';
import '../repositories/notification_repository.dart';

/// Nhận FCM push khi có đơn mới (order_offer/order_auto_confirmed/order_auto_cancelled) và
/// điều hướng thẳng tới màn tương ứng — kể cả khi app đang mở (foreground), đang nền, hay
/// đã bị tắt hẳn (terminated). Payload data đến từ server/src/orderOffer.js.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // flutter_local_notifications không hỗ trợ web — trên web, thông báo lúc app đang mở
    // (foreground) do trình duyệt tự xử lý qua firebase-messaging-sw.js, không cần hiển
    // thị thủ công; lúc app nền/đóng thì service worker lo hết, Dart code không chạy.
    if (!kIsWeb) {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null)
            handleData(jsonDecode(response.payload!) as Map<String, dynamic>);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'order_offers',
              'Đơn hàng',
              description:
                  'Thông báo đơn mới, đơn tự xác nhận, đơn tự huỷ do quá hạn',
              importance: Importance.max,
            ),
          );
    }

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
      WidgetsBinding.instance.addPostFrameCallback((_) => handleData(initial.data));
    }
  }

  Future<void> _registerTokenIfLoggedIn() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      // vapidKey chỉ web cần (lấy từ Firebase Console > Cloud Messaging > Web Push
      // certificates) — mobile bỏ qua tham số này.
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? Env.firebaseVapidKey : null,
      );
      if (token != null) await DeviceRepository().registerPushToken(token);
    } catch (e) {
      debugPrint('[push] Không đăng ký được push token: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    // flutter_local_notifications không hỗ trợ web — trình duyệt tự lo lúc foreground.
    if (!kIsWeb) {
      final title = message.notification?.title ?? message.data['title'];
      final body = message.notification?.body ?? message.data['body'];
      if (title != null) {
        await _local.show(
          message.hashCode,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'order_offers',
              'Đơn hàng',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: jsonEncode(message.data),
        );
      }
    }
    // Đơn mới cần xác nhận: mở thẳng màn nhận đơn, không chờ người dùng bấm vào thông báo —
    // đúng kiểu Grab/Shopee (app tự bật lên khi đang mở sẵn). Áp dụng cả trên web.
    if (message.data['type'] == 'order_offer') handleData(message.data);
  }

  void handleData(Map<String, dynamic> data) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    // Thông báo admin gửi tay (màn "Thông báo" ở web admin) — screen là route admin tự chọn
    // lúc soạn thông báo, không liên quan gì đơn hàng nên phải xét trước nhánh order_id.
    if (data['type'] == 'admin_broadcast') {
      final screen = data['screen'] as String?;
      if (screen != null && screen.isNotEmpty) context.go(screen);
      return;
    }
    final orderId = data['order_id'] as String?;
    if (orderId == null) return;

    // Bấm thẳng push (ngoài màn hình chính) cũng tính là đã đọc, giống bấm trong danh sách
    // hộp thư — notification_id do server nhét sẵn vào data (xem push.js sendPushToUser),
    // không cần thêm bước tra cứu API nào khác.
    final notificationId = data['notification_id'] as String?;
    if (notificationId != null) {
      NotificationRepository().markRead(notificationId).catchError((_) {});
    }

    switch (data['type']) {
      case 'order_offer':
        context.push('/orders/offer/$orderId');
        break;
      case 'order_auto_confirmed':
      case 'order_auto_cancelled':
        context.go('/orders/$orderId');
        break;
    }
  }
}
