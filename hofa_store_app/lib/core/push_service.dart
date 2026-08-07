import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';
import 'format.dart';
import '../models/user_device.dart';
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

    // Đợi runApp() vẽ xong khung hình đầu (như getInitialMessage bên dưới) — _registerDevice
    // có thể cần mở dialog hỏi gỡ thiết bị cũ (đạt giới hạn max_devices), gọi ngay lúc này thì
    // navigatorKey.currentContext vẫn null vì init() được await TRƯỚC runApp() (xem main.dart).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _registerTokenIfLoggedIn(),
    );
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
      if (token != null) await _registerDevice(token);
    } catch (e) {
      debugPrint('[push] Không đăng ký được push token: $e');
    }
  }

  /// Đăng ký thiết bị — nếu cửa hàng đã đủ max_devices thiết bị, server từ chối và trả về
  /// thiết bị cũ nhất; hỏi người dùng có muốn gỡ nó để đăng ký thiết bị này hay không. Từ
  /// chối thì không đăng ký được push trên máy này (KHÔNG chặn dùng app), tránh trường hợp
  /// nhiều thiết bị cùng nhận trùng thông báo đơn hàng.
  Future<void> _registerDevice(
    String token, {
    bool forceReplaceOldest = false,
  }) async {
    final result = await DeviceRepository().registerPushToken(
      token,
      forceReplaceOldest: forceReplaceOldest,
    );
    if (!result.limitReached) return;

    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Đã đạt giới hạn thiết bị'),
        content: Text(
          'Cửa hàng này chỉ được đăng nhập tối đa ${result.maxDevices} thiết bị nhận thông '
          'báo cùng lúc. Gỡ thiết bị đăng nhập cũ nhất '
          '("${result.oldestDeviceName?.isNotEmpty == true ? result.oldestDeviceName : 'Thiết bị không tên'}"'
          '${result.oldestDevicePlatform != null ? ' · ${devicePlatformLabels[result.oldestDevicePlatform] ?? result.oldestDevicePlatform}' : ''}'
          '${result.oldestDeviceLastActive != null ? ', hoạt động lần cuối ${formatDateTime(result.oldestDeviceLastActive!)}' : ''}'
          ') để thiết bị này nhận thông báo thay?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gỡ và tiếp tục'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _registerDevice(token, forceReplaceOldest: true);
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

    // notification_id do server nhét sẵn vào data (xem push.js sendPushToUser) — bấm thẳng
    // push (ngoài màn hình chính) tính là đã đọc GIỐNG bấm trong danh sách hộp thư, TRỪ
    // order_offer: mở màn nhận đơn ra chưa có nghĩa là đã xử lý, nếu bấm X bỏ qua mà chưa
    // trượt nhận/huỷ thì badge đỏ phải còn nguyên — order_offer_screen.dart tự đánh dấu đã
    // đọc khi thực sự nhận/huỷ xong (xem OrderOfferScreen.notificationId).
    final notificationId = data['notification_id'] as String?;
    final isOrderOffer = data['type'] == 'order_offer';
    if (notificationId != null && !isOrderOffer) {
      NotificationRepository().markRead(notificationId).catchError((_) {});
    }

    switch (data['type']) {
      case 'order_offer':
        context.push('/orders/offer/$orderId', extra: notificationId);
        break;
      case 'order_auto_confirmed':
      case 'order_auto_cancelled':
        context.go('/orders/$orderId');
        break;
    }
  }
}
