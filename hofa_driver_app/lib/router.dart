import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'main.dart' show navigatorKey;
import 'providers/auth_provider.dart';
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
    initialLocation: '/',
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
