import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';
import 'format.dart';
import 'pending_deep_link.dart';
import '../models/user_device.dart';
import '../repositories/device_repository.dart';
import '../repositories/notification_repository.dart';

/// Nhận FCM push khi có đơn mới (order_offer/order_auto_confirmed/order_auto_cancelled) và
/// điều hướng thẳng tới màn tương ứng — kể cả khi app đang mở (foreground), đang nền, hay
/// đã bị tắt hẳn (terminated). Payload data đến từ server/src/orderOffer.js.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // Kênh Android + tên file âm thanh iOS riêng cho đơn mới (order_offer) — phải khớp CHÍNH XÁC
  // với server/src/orderOffer.js (NEW_ORDER_ANDROID_CHANNEL/NEW_ORDER_SOUND_IOS) và file thật đã
  // đóng gói: android/app/src/main/res/raw/new_order_alert.mp3, ios/Runner/new_order_alert.caf.
  static const _kNewOrderChannelId = 'new_order_alert';
  static const _kNewOrderSoundIOS = 'new_order_alert.caf';

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

  // Cùng lý do chatMessageStream ở trên — màn danh sách/chi tiết đơn đang mở sẵn tự làm mới
  // NGAY khi có push đơn mới/đổi trạng thái, thay vì phải thoát ra vào lại.
  final _orderEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get orderEventStream =>
      _orderEventController.stream;

  // order_id của khung chat đang mở trên màn hình — khỏi hiện thông báo hệ thống trùng lặp khi
  // cửa hàng đang xem đúng đoạn chat đó (tin đã tự cập nhật ngay trong màn).
  String? _openChatOrderId;
  void setOpenChat(String? orderId) => _openChatOrderId = orderId;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // Không await — hộp thoại xin quyền cần người dùng bấm mới xong (có thể mất rất lâu,
    // hoặc treo hẳn nếu không ai tương tác); đăng ký token/lắng nghe bên dưới không được
    // phép phụ thuộc vào lúc nào người dùng mới bấm hộp thoại này.
    unawaited(_requestPermissionSafely());

    // flutter_local_notifications không hỗ trợ web — trên web, thông báo lúc app đang mở
    // (foreground) do trình duyệt tự xử lý qua firebase-messaging-sw.js, không cần hiển
    // thị thủ công; lúc app nền/đóng thì service worker lo hết, Dart code không chạy.
    if (!kIsWeb) {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Tắt 3 cờ request*Permission mặc định (true) — flutter_local_notifications tự mở
          // thêm 1 hộp thoại xin quyền RIÊNG khi initialize() nếu không tắt, trùng với hộp
          // thoại FirebaseMessaging.requestPermission() ở trên và cũng chờ người dùng bấm y
          // hệt, khiến bước này bị treo nếu không có ai tương tác ngay lúc mở app.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null)
            handleData(jsonDecode(response.payload!) as Map<String, dynamic>);
        },
      );
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'order_offers',
          'Đơn hàng',
          description:
              'Thông báo đơn mới, đơn tự xác nhận, đơn tự huỷ do quá hạn',
          importance: Importance.max,
        ),
      );
      // Kênh RIÊNG chỉ cho đơn mới (order_offer) — âm thanh do bạn tải lên (Tài nguyên/Notification
      // cửa hàng.mp3, đặt tên lại thành new_order_alert). Android khoá âm thanh vào kênh ngay lúc
      // tạo (immutable) nên phải tách kênh riêng thay vì đổi âm của "order_offers" — nếu sau này
      // đổi file âm thanh khác thì phải đổi luôn ID kênh (vd new_order_alert_v2) mới có tác dụng
      // với máy đã cài trước đó, chỉ đổi tên file thôi Android không nhận ra kênh đã đổi.
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kNewOrderChannelId,
          'Đơn hàng mới',
          description: 'Âm thanh riêng khi có đơn hàng mới cần xác nhận',
          importance: Importance.max,
          sound: RawResourceAndroidNotificationSound('new_order_alert'),
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

    final initial = await FirebaseMessaging.instance.getInitialMessage().timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
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

  Future<void> _requestPermissionSafely() async {
    try {
      await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[push] requestPermission lỗi/chưa xong: $e');
    }
  }

  Future<void> _registerTokenIfLoggedIn() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      // iOS: getToken() cần APNs token đã sẵn sàng TRƯỚC (Apple cấp qua mạng sau khi quyền
      // được cấp, có độ trễ vài trăm ms tới vài giây) — gọi quá sớm ném lỗi thẳng
      // 'apns-token-not-set' và KHÔNG tự thử lại, khiến thiết bị không bao giờ đăng ký được
      // push dù quyền đã cấp (xác nhận qua log thật: race với _requestPermissionSafely() ở
      // init(), 2 việc chạy gần như cùng lúc lúc mở app). Đợi tối đa 30s cho APNs token trước
      // khi gọi getToken() — quá thời gian đó thì bỏ qua lần này, lần gọi lại tiếp theo
      // (onTokenRefresh/onAuthStateChange) sẽ thử lại.
      if (!kIsWeb && Platform.isIOS) {
        var apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        for (var i = 0; apnsToken == null && i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        }
        if (apnsToken == null) {
          debugPrint('[push] Chưa có APNs token sau 30s — bỏ qua, đợi lần gọi lại tiếp theo.');
          return;
        }
      }
      // vapidKey chỉ web cần (lấy từ Firebase Console > Cloud Messaging > Web Push
      // certificates) — mobile bỏ qua tham số này.
      final token = await FirebaseMessaging.instance
          .getToken(vapidKey: kIsWeb ? Env.firebaseVapidKey : null)
          .timeout(const Duration(seconds: 15));
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
    // Không có thiết bị nào của CHỦ để tự gỡ (server chỉ tự gỡ thiết bị chủ, không đụng tới
    // thiết bị nhân viên đang làm việc — xem POST /devices) — báo rõ, không cho bấm "Gỡ và
    // tiếp tục" vì bấm cũng sẽ bị server từ chối lại.
    final canAutoReplace = result.oldestDeviceName != null;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Đã đạt giới hạn thiết bị'),
        content: Text(
          canAutoReplace
              ? 'Cửa hàng này chỉ được đăng nhập tối đa ${result.maxDevices} thiết bị nhận '
                    'thông báo cùng lúc. Gỡ thiết bị đăng nhập cũ nhất '
                    '("${result.oldestDeviceName!.isNotEmpty ? result.oldestDeviceName : 'Thiết bị không tên'}"'
                    '${result.oldestDevicePlatform != null ? ' · ${devicePlatformLabels[result.oldestDevicePlatform] ?? result.oldestDevicePlatform}' : ''}'
                    '${result.oldestDeviceLastActive != null ? ', hoạt động lần cuối ${formatDateTime(result.oldestDeviceLastActive!)}' : ''}'
                    ') để thiết bị này nhận thông báo thay?'
              : 'Cửa hàng này chỉ được đăng nhập tối đa ${result.maxDevices} thiết bị nhận '
                    'thông báo cùng lúc — toàn bộ thiết bị hiện tại đều của nhân viên nên '
                    'không tự gỡ được. Vào màn "Thiết bị" để gỡ tay 1 máy trước.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(canAutoReplace ? 'Để sau' : 'Đã hiểu'),
          ),
          if (canAutoReplace)
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
        // Đơn mới dùng kênh/âm thanh riêng (Tài nguyên/Notification cửa hàng.mp3) — mọi loại
        // thông báo khác vẫn giữ âm mặc định của kênh "order_offers" như trước giờ.
        final isNewOrder = message.data['type'] == 'order_offer';
        await _local.show(
          message.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              isNewOrder ? _kNewOrderChannelId : 'order_offers',
              isNewOrder ? 'Đơn hàng mới' : 'Đơn hàng',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              sound: isNewOrder ? _kNewOrderSoundIOS : null,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    }
    // Đơn mới: mở thẳng màn chi tiết đơn, không chờ người dùng bấm vào thông báo — đúng kiểu
    // Grab/Shopee (app tự bật lên khi đang mở sẵn). Áp dụng cả trên web.
    if (message.data['type'] == 'order_offer') handleData(message.data);
    const orderEventTypes = {
      'order_offer',
      'order_auto_confirmed',
      'order_auto_cancelled',
      'order_upcoming',
    };
    if (orderEventTypes.contains(message.data['type'])) {
      _orderEventController.add(message.data);
    }
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
    // push (ngoài màn hình chính) tính là đã đọc, giống bấm trong danh sách hộp thư.
    final notificationId = data['notification_id'] as String?;
    if (notificationId != null) {
      NotificationRepository().markRead(notificationId).catchError((_) {});
    }

    switch (data['type']) {
      case 'order_offer':
      case 'order_auto_confirmed':
      case 'order_auto_cancelled':
      // Đơn đặt trước còn "ngủ" — chỉ xem trước, order_detail_screen.dart tự ẩn hết nút hành
      // động (scheduled_activated_at NULL), không auto-mở khi app đang foreground (khác
      // order_offer ở nhánh trên, xem _onForegroundMessage) vì chưa cần gấp.
      case 'order_upcoming':
        context.go('/orders/$orderId');
        break;
      case 'chat_message':
        context.push('/orders/$orderId/chat');
        break;
    }
  }
}
