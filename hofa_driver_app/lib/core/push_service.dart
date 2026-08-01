import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/device_repository.dart';

/// Nhận FCM push khi có đơn mới (delivery_offer/delivery_assigned) và điều hướng
/// thẳng tới màn tương ứng — kể cả khi app đang mở (foreground), đang nền, hay đã
/// bị tắt hẳn (terminated). Payload data đến từ server/src/push.js.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) _handleData(jsonDecode(response.payload!) as Map<String, dynamic>);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'delivery_offers',
          'Đơn giao hàng',
          description: 'Thông báo đơn mới, đơn được gán, cập nhật chuyến giao',
          importance: Importance.max,
        ));

    await _registerTokenIfLoggedIn();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerTokenIfLoggedIn());
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => _registerTokenIfLoggedIn());

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleData(m.data));

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleData(initial.data);
  }

  Future<void> _registerTokenIfLoggedIn() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await DeviceRepository().registerPushToken(token);
    } catch (e) {
      debugPrint('[push] Không đăng ký được push token: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title != null) {
      await _local.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('delivery_offers', 'Đơn giao hàng', importance: Importance.max, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
    // Đơn mới cần xác nhận: mở thẳng màn nhận đơn, không chờ người dùng bấm vào thông báo —
    // đúng kiểu Grab/Shopee (app tự bật lên khi đang mở sẵn).
    if (message.data['type'] == 'delivery_offer') _handleData(message.data);
  }

  void _handleData(Map<String, dynamic> data) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final deliveryId = data['delivery_id'] as String?;
    if (deliveryId == null) return;

    switch (data['type']) {
      case 'delivery_offer':
        context.push('/offer/$deliveryId');
        break;
      case 'delivery_assigned':
        context.go('/deliveries/$deliveryId');
        break;
    }
  }
}
