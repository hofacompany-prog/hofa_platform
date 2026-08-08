import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'main.dart' show navigatorKey;
import 'providers/auth_provider.dart';
import 'providers/delivery_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_driver_screen.dart';
import 'screens/shell/driver_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/delivery/delivery_detail_screen.dart';
import 'screens/offer/offer_screen.dart';
import 'screens/notifications/notifications_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    // initialLocation cố định từng khiến app LUÔN boot ở trang chủ bất kể trình duyệt/PWA
    // thực sự mở ở URL nào — kể cả khi service worker đã điều hướng
    // clients.openWindow()/client.navigate() đúng tới /offer/:id hay /deliveries/:id lúc bấm
    // push (xem web/firebase-messaging-sw.js), route đó vẫn bị initialLocation ghi đè ngay
    // khi GoRouter khởi tạo. Trên web, ưu tiên URL thật của trình duyệt lúc mở app.
    initialLocation: kIsWeb && Uri.base.path.length > 1 ? Uri.base.path : '/',
    refreshListenable: GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      final onRegister = state.matchedLocation == '/register-driver';

      if (session == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';

      try {
        final profile = await ref.read(userProfileProvider.future);
        final driver = profile == null ? null : await ref.read(myDriverProvider.future);
        if (driver == null) return onRegister ? null : '/register-driver';
        if (onRegister) return '/';
      } catch (_) {
        // lỗi mạng tạm thời — đừng khoá cứng người dùng
      }

      // Đang có màn nhận đơn chờ quyết định — ép ở lại đúng màn đó bất kể thoát ra bằng cách
      // nào (nút back trình duyệt, sửa tay URL...), xem pendingOfferIdProvider.
      final pendingOfferId = ref.read(pendingOfferIdProvider);
      if (pendingOfferId != null && state.matchedLocation != '/offer/$pendingOfferId') {
        return '/offer/$pendingOfferId';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register-driver', builder: (context, state) => const RegisterDriverScreen()),
      GoRoute(
        path: '/offer/:deliveryId',
        builder: (context, state) => OfferScreen(deliveryId: state.pathParameters['deliveryId']!),
      ),
      GoRoute(
        path: '/deliveries/:id',
        builder: (context, state) => DeliveryDetailScreen(deliveryId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) => DriverShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/earnings', builder: (context, state) => const EarningsScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
        ],
      ),
    ],
  );
});
