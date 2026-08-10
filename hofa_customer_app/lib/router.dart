import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'core/pwa_install_service.dart';
import 'providers/auth_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/install/install_pwa_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/shell/customer_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/merchant/merchant_detail_screen.dart';
import 'screens/merchant/merchant_reviews_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/preorder/preorder_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'models/preorder_schedule.dart';
import 'models/buy_now_request.dart';
import 'screens/orders/orders_list_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/categories/all_categories_screen.dart';
import 'screens/categories/category_detail_screen.dart';
import 'screens/categories/category_products_screen.dart';
import 'screens/favorites/favorite_merchants_screen.dart';
import 'main.dart' show navigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    // initialLocation cố định từng khiến app LUÔN boot ở trang chủ bất kể trình duyệt/PWA
    // thực sự mở ở URL nào — kể cả khi service worker đã điều hướng
    // clients.openWindow()/client.navigate() đúng tới /orders/:id lúc bấm push (xem
    // web/firebase-messaging-sw.js), route đó vẫn bị initialLocation ghi đè ngay khi
    // GoRouter khởi tạo. Trên web, ưu tiên URL thật của trình duyệt lúc mở app.
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

      if (session == null) return loggingIn ? null : '/login';

      try {
        final profile = await ref.read(userProfileProvider.future);
        if (profile == null) {
          if (ref.read(authFlowInProgressProvider)) return null;
          return completingProfile ? null : '/complete-profile';
        }
        if (loggingIn || completingProfile) return '/';
      } catch (_) {
        // lỗi mạng tạm thời — đừng khoá cứng người dùng
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
      ShellRoute(
        builder: (context, state, child) => CustomerShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/merchants/:id',
            builder: (context, state) =>
                MerchantDetailScreen(merchantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/merchants/:id/reviews',
            builder: (context, state) =>
                MerchantReviewsScreen(merchantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: '/preorder',
            builder: (context, state) => const PreorderScreen(),
          ),
          GoRoute(
            path: '/checkout',
            builder: (context, state) {
              final extra = state.extra;
              return CheckoutScreen(
                preorderSchedule: extra is PreorderSchedule ? extra : null,
                initialScheduledFor: extra is DateTime ? extra : null,
                buyNowRequest: extra is BuyNowRequest ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersListScreen(),
          ),
          GoRoute(
            path: '/orders/:id',
            // ?status=delivered — chỉ gắn khi khách mở màn này TỪ đúng thông báo "Giao hàng
            // thành công" (xem push_service.dart#handleData + firebase-messaging-sw.js),
            // dùng để tự bật popup mời đánh giá, không hiện lúc khách tự bấm vào xem đơn.
            builder: (context, state) => OrderDetailScreen(
              orderId: state.pathParameters['id']!,
              autoPromptReview:
                  state.uri.queryParameters['status'] == 'delivered',
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/favorites',
            builder: (context, state) => const FavoriteMerchantsScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const AllCategoriesScreen(),
          ),
          GoRoute(
            path: '/categories/:id',
            builder: (context, state) => CategoryDetailScreen(
              categoryId: state.pathParameters['id']!,
              categoryName: state.extra as String?,
            ),
          ),
          GoRoute(
            path: '/categories/:id/children',
            builder: (context, state) => AllCategoriesScreen(
              parentId: state.pathParameters['id']!,
              parentName: state.extra as String?,
            ),
          ),
          GoRoute(
            path: '/categories/:id/products',
            builder: (context, state) => CategoryProductsScreen(
              categoryId: state.pathParameters['id']!,
              categoryName: state.extra as String?,
            ),
          ),
        ],
      ),
    ],
  );
});
