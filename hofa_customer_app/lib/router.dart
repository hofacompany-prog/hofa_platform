import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'providers/auth_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/shell/customer_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/merchant/merchant_detail_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/preorder/preorder_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'models/preorder_schedule.dart';
import 'screens/orders/orders_list_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/categories/all_categories_screen.dart';
import 'screens/categories/category_detail_screen.dart';
import 'screens/categories/category_products_screen.dart';
import 'main.dart' show navigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      final completingProfile = state.matchedLocation == '/complete-profile';

      if (session == null) return loggingIn ? null : '/login';

      try {
        final profile = await ref.read(userProfileProvider.future);
        if (profile == null)
          return completingProfile ? null : '/complete-profile';
        if (loggingIn || completingProfile) return '/';
      } catch (_) {
        // lỗi mạng tạm thời — đừng khoá cứng người dùng
      }
      return null;
    },
    routes: [
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
              );
            },
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersListScreen(),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (context, state) =>
                OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
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
