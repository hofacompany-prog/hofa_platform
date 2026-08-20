import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'providers/admin_providers.dart';
import 'models/merchant.dart';
import 'screens/auth/admin_login_screen.dart';
import 'screens/dashboard/admin_shell.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/merchants/merchant_hub_screen.dart';
import 'screens/merchants/merchant_form_screen.dart';
import 'screens/merchants/merchant_detail_screen.dart';
import 'screens/merchants/merchant_products_screen.dart';
import 'screens/merchants/merchant_product_form_screen.dart';
import 'screens/merchants/featured_merchants_screen.dart';
import 'screens/merchants/branch_hours_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/orders/order_blocking_records_screen.dart';
import 'screens/users/users_screen.dart';
import 'screens/users/user_detail_screen.dart';
import 'screens/drivers/driver_hub_screen.dart';
import 'screens/deliveries/delivery_detail_screen.dart';
import 'screens/catalog/categories_hub_screen.dart';
import 'screens/settings/finance_hub_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/notifications/my_notifications_screen.dart';

final adminNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: adminNavigatorKey,
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';

      if (session == null) return loggingIn ? null : '/login';

      // Đã đăng nhập nhưng chưa chắc là admin — mọi endpoint bên trong đều
      // yêu cầu role admin nên chặn ngay ở đây cho rõ ràng thay vì để lỗi 403 rải rác.
      try {
        final profile = await ref.read(userProfileProvider.future);
        if (profile?.role != 'admin') {
          await Supabase.instance.client.auth.signOut();
          return '/login';
        }
      } catch (_) {
        return null; // lỗi mạng tạm thời — đừng đá người dùng ra ngoài
      }

      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/merchants',
            builder: (context, state) => MerchantHubScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: '/merchants/new',
            builder: (context, state) => const MerchantFormScreen(),
          ),
          GoRoute(
            path: '/merchants/featured-home',
            builder: (context, state) => const FeaturedMerchantsScreen(),
          ),
          GoRoute(
            path: '/merchants/:id',
            builder: (context, state) =>
                MerchantDetailScreen(merchantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/merchants/:id/products',
            builder: (context, state) => MerchantProductsScreen(
              merchant: state.extra as Merchant,
            ),
          ),
          GoRoute(
            path: '/merchants/:id/products/new',
            builder: (context, state) => MerchantProductFormScreen(
              merchant: state.extra as Merchant,
            ),
          ),
          GoRoute(
            path: '/merchants/:id/products/:productId/edit',
            builder: (context, state) => MerchantProductFormScreen(
              merchant: state.extra as Merchant,
              productId: state.pathParameters['productId']!,
            ),
          ),
          GoRoute(
            path: '/merchants/:id/branches/:branchId/hours',
            builder: (context, state) => BranchHoursScreen(
              merchantId: state.pathParameters['id']!,
              branchId: state.pathParameters['branchId']!,
            ),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (context, state) =>
                AdminOrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/orders/:id/blocking-records',
            builder: (context, state) => OrderBlockingRecordsScreen(
              orderId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/users/:id',
            builder: (context, state) =>
                UserDetailScreen(userId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/drivers',
            builder: (context, state) => DriverHubScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: '/deliveries/:id',
            builder: (context, state) =>
                DeliveryDetailScreen(deliveryId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => CategoriesHubScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: '/finance',
            builder: (context, state) => FinanceHubScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/my-notifications',
            builder: (context, state) => const MyNotificationsScreen(),
          ),
        ],
      ),
    ],
  );
});
