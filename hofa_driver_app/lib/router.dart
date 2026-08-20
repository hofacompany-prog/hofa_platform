import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'core/pwa_install_service.dart';
import 'main.dart' show navigatorKey;
import 'providers/auth_provider.dart';
import 'providers/delivery_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/auth/register_driver_screen.dart';
import 'screens/install/install_pwa_screen.dart';
import 'screens/shell/driver_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/earnings/wallet_history_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/delivery/delivery_detail_screen.dart';
import 'screens/delivery/delivery_map_screen.dart';
import 'screens/merchant/report_price_screen.dart';
import 'screens/delivery/chat_screen.dart';
import 'screens/offer/offer_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/shortcut/shortcut_status_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    // initialLocation cố định từng khiến app LUÔN boot ở trang chủ bất kể trình duyệt/PWA
    // thực sự mở ở URL nào — kể cả khi service worker đã điều hướng
    // clients.openWindow()/client.navigate() đúng tới /offer/:id hay /deliveries/:id lúc bấm
    // push (xem web/firebase-messaging-sw.js), route đó vẫn bị initialLocation ghi đè ngay
    // khi GoRouter khởi tạo. Trên web, ưu tiên URL thật của trình duyệt lúc mở app.
    initialLocation: kIsWeb && Uri.base.path.length > 1 ? Uri.base.path : '/',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      // Bắt buộc cài PWA trước khi dùng bất cứ gì khác (kể cả đăng nhập) — chỉ áp dụng khi
      // trình duyệt thực sự có cách cài (Android/Chrome hoặc bất kỳ trình duyệt nào trên iOS),
      // desktop không hỗ trợ (Firefox, Safari desktop...) thì không bị chặn. Đã từng cài
      // (appinstalled, xem PwaInstallService.wasInstalledPreviously) mà vẫn đang mở bằng trình
      // duyệt thường (chưa mở từ icon màn hình chính) thì cũng vào màn này — InstallPwaScreen
      // tự đổi sang thông báo "mở app ngoài màn hình" thay vì hỏi cài lại.
      final needsInstall =
          !PwaInstallService.isStandalone() &&
          (PwaInstallService.wasInstalledPreviously() ||
              PwaInstallService.hasDeferredPrompt() ||
              PwaInstallService.isIOS());
      if (needsInstall) {
        return state.matchedLocation == '/install-pwa' ? null : '/install-pwa';
      }
      if (state.matchedLocation == '/install-pwa') return '/';

      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      final completingProfile = state.matchedLocation == '/complete-profile';
      final onRegister = state.matchedLocation == '/register-driver';

      if (session == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';

      try {
        final profile = await ref.read(userProfileProvider.future);
        // SĐT này có thể đã có tài khoản Auth (đã là khách/chủ cửa hàng ở app khác) nhưng CHƯA
        // có hồ sơ users role='driver' — vd vừa bấm "Đăng nhập" (không phải "Đăng ký") ở app
        // Tài xế lần đầu. Tạo hồ sơ driver riêng trước khi vào /register-driver, xem
        // hofa-db/90_multi_role_accounts.sql.
        if (profile == null) {
          return completingProfile ? null : '/complete-profile';
        }
        final driver = await ref.read(myDriverProvider.future);
        if (driver == null) return onRegister ? null : '/register-driver';
        if (onRegister || completingProfile) return '/';
      } catch (_) {
        // lỗi mạng tạm thời — đừng khoá cứng người dùng
      }

      // Đang có màn nhận đơn chờ quyết định — ép ở lại đúng màn đó bất kể thoát ra bằng cách
      // nào (nút back trình duyệt, sửa tay URL...), xem pendingOfferIdProvider.
      final pendingOfferId = ref.read(pendingOfferIdProvider);
      if (pendingOfferId != null &&
          state.matchedLocation != '/offer/$pendingOfferId') {
        return '/offer/$pendingOfferId';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/install-pwa',
        builder: (context, state) => const InstallPwaScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/register-driver',
        builder: (context, state) => const RegisterDriverScreen(),
      ),
      // Sửa/nộp lại hồ sơ sau khi bị admin từ chối — khác /register-driver (route đó luôn bị
      // redirect() đá về '/' nếu đã có bản ghi drivers, xem redirect ở trên).
      GoRoute(
        path: '/edit-driver-profile',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) {
            final driverAsync = ref.watch(myDriverProvider);
            return driverAsync.when(
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Scaffold(body: Center(child: Text('Lỗi: $e'))),
              data: (driver) => RegisterDriverScreen(existing: driver),
            );
          },
        ),
      ),
      GoRoute(
        path: '/offer/:deliveryId',
        builder: (context, state) =>
            OfferScreen(deliveryId: state.pathParameters['deliveryId']!),
      ),
      GoRoute(
        path: '/deliveries/:id',
        builder: (context, state) =>
            DeliveryDetailScreen(deliveryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/deliveries/:id/map',
        builder: (context, state) =>
            DeliveryMapScreen(deliveryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/merchants/:id/report-price',
        builder: (context, state) =>
            ReportPriceScreen(merchantId: state.pathParameters['id']!),
      ),
      GoRoute(
        // Truy cập CHỈ qua nút trong chi tiết chuyến, không có hộp thư riêng — id ở đây là
        // order_id (không phải delivery_id) — xem hofa-db/74_order_chat.sql.
        path: '/orders/:id/chat',
        builder: (context, state) =>
            ChatScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/wallet/history',
        builder: (context, state) => const WalletHistoryScreen(),
      ),
      // Đích của 2 shortcut PWA "Bật/Tắt nhận đơn" (bấm giữ icon app, xem web/manifest.json).
      GoRoute(
        path: '/shortcut-online',
        builder: (context, state) => const ShortcutStatusScreen(goOnline: true),
      ),
      GoRoute(
        path: '/shortcut-offline',
        builder: (context, state) =>
            const ShortcutStatusScreen(goOnline: false),
      ),
      ShellRoute(
        builder: (context, state, child) => DriverShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/earnings',
            builder: (context, state) => const EarningsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
        ],
      ),
    ],
  );
});
