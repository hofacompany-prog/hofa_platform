import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';
import 'pending_deep_link.dart';
import '../repositories/device_repository.dart';

/// Nhận FCM push khi có đơn mới (delivery_offer/delivery_assigned) và điều hướng
/// thẳng tới màn tương ứng — kể cả khi app đang mở (foreground), đang nền, hay đã
/// bị tắt hẳn (terminated). Payload data đến từ server/src/push.js.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  // Đẩy tin nhắn mới cho đúng màn chat đang mở (nếu có) cập nhật ngay lập tức thay vì đợi
  // polling — thay được nhờ giờ là app native thật, FCM foreground đáng tin cậy hơn hẳn PWA.
  // Không dùng Supabase Realtime (dữ liệu nghiệp vụ chỉ đi qua Express API, xem CLAUDE.md),
  // tận dụng thẳng hạ tầng push sẵn có (server/src/push.js đã gửi kèm order_id).
  final _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatMessageStream =>
      _chatMessageController.stream;

  // order_id của khung chat đang mở trên màn hình — khỏi hiện thông báo hệ thống trùng lặp khi
  // tài xế đang xem đúng đoạn chat đó (tin đã tự cập nhật ngay trong màn).
  String? _openChatOrderId;
  void setOpenChat(String? orderId) => _openChatOrderId = orderId;

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
              'delivery_offers',
              'Đơn giao hàng',
              description:
                  'Thông báo đơn mới, đơn được gán, cập nhật chuyến giao',
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => handleData(initial.data),
      );
    }
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkPendingDeepLink(),
      );
      // App đang mở nền rồi bấm push: xem setPendingDeepLinkMessageHandler trong
      // pending_deep_link_web.dart để hiểu vì sao cần thêm kênh này ngoài lần đọc lúc khởi động.
      PendingDeepLink.onMessage(_checkPendingDeepLink);
    }
  }

  /// Bù cho getInitialMessage() ở trên — trên web, lúc app cài kiểu PWA/WebAPK bị tắt hẳn rồi
  /// mở lại từ việc bấm 1 thông báo, getInitialMessage() không đáng tin cậy (đã xác nhận: app
  /// mở lên nhưng luôn rơi về trang chủ). firebase-messaging-sw.js tự ghi lại đường dẫn cần
  /// tới vào IndexedDB ngay lúc bấm (xem writePendingDeepLink) — đọc lại ở đây để tự điều
  /// hướng, độc lập hoàn toàn với getInitialMessage().
  Future<void> _checkPendingDeepLink() async {
    final path = await PendingDeepLink.readAndClear();
    if (path == null || path.isEmpty || path == '/') return;
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    context.go(path);
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
    if (message.data['type'] == 'chat_message') {
      _chatMessageController.add(message.data);
      // Đang mở đúng khung chat này — tin đã tự chèn vào màn qua chatMessageStream ở trên,
      // khỏi hiện thêm thông báo hệ thống trùng lặp.
      if (message.data['order_id'] == _openChatOrderId) return;
    }
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
              'delivery_offers',
              'Đơn giao hàng',
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
    if (message.data['type'] == 'delivery_offer') handleData(message.data);
  }

  void handleData(Map<String, dynamic> data) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    // Thông báo admin gửi tay (màn "Thông báo" ở web admin) — screen là route admin tự chọn
    // lúc soạn thông báo, không liên quan gì chuyến giao nên phải xét trước nhánh delivery_id.
    if (data['type'] == 'admin_broadcast') {
      final screen = data['screen'] as String?;
      if (screen != null && screen.isNotEmpty) context.go(screen);
      return;
    }
    // Hồ sơ bị từ chối — mở trang chủ, nơi có banner + nút "Sửa hồ sơ" (xem home_screen.dart).
    if (data['type'] == 'driver_verification_rejected') {
      context.go('/');
      return;
    }
    // Kết quả duyệt nạp/rút ví — mở màn Ví để tài xế thấy số dư mới.
    if (data['type'] == 'driver_wallet_update') {
      context.push('/earnings');
      return;
    }
    // Tin nhắn mới từ khách — payload dùng order_id (không phải delivery_id), xem
    // hofa-db/74_order_chat.sql.
    if (data['type'] == 'chat_message') {
      final orderId = data['order_id'] as String?;
      if (orderId != null) context.push('/orders/$orderId/chat');
      return;
    }
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
