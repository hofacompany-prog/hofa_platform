import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding/create_store_screen.dart';
import 'screens/dashboard/dashboard_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/products/products_list_screen.dart';
import 'screens/products/product_form_screen.dart';
import 'screens/toppings/topping_group_form_screen.dart';
import 'screens/orders/orders_list_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/orders/order_offer_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/settings/branch_settings_screen.dart';
import 'screens/settings/store_profile_edit_screen.dart';
import 'screens/settings/branch_edit_screen.dart';
import 'screens/settings/branch_hours_screen.dart';
import 'screens/settings/devices_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'models/merchant.dart';
import 'models/branch.dart';
import 'main.dart' show navigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      final onOnboarding = state.matchedLocation == '/onboarding';

      if (session == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/home';

      try {
        final profile = await ref.read(userProfileProvider.future);
        // Chưa có hồ sơ public.users — xảy ra khi đăng ký xong nhưng phải xác nhận
        // email rồi mới đăng nhập lại (lúc đăng ký session=null nên chưa gọi được
        // auth.syncProfile). Gom chung với "chưa có cửa hàng": CreateStoreScreen lo cả 2.
        if (profile == null) return onOnboarding ? null : '/onboarding';

        final merchant = await ref.read(myMerchantProvider.future);
        if (merchant == null && !onOnboarding) return '/onboarding';
        if (merchant != null && onOnboarding) return '/home';
      } catch (_) {
        // lỗi mạng tạm thời — đừng khoá cứng người dùng
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const CreateStoreScreen(),
      ),
      GoRoute(
        path: '/orders/offer/:id',
        builder: (context, state) => OrderOfferScreen(
          orderId: state.pathParameters['id']!,
          notificationId: state.extra as String?,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => DashboardShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsListScreen(),
          ),
          GoRoute(
            path: '/products/new',
            builder: (context, state) => const ProductFormScreen(),
          ),
          GoRoute(
            path: '/products/:id/edit',
            builder: (context, state) =>
                ProductFormScreen(productId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/topping-groups/new',
            builder: (context, state) => const ToppingGroupFormScreen(),
          ),
          GoRoute(
            path: '/topping-groups/:id/edit',
            builder: (context, state) =>
                ToppingGroupFormScreen(groupId: state.pathParameters['id']),
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
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/finance',
            builder: (context, state) => const FinanceScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const BranchSettingsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/settings/devices',
            builder: (context, state) => const DevicesScreen(),
          ),
          GoRoute(
            path: '/settings/profile',
            builder: (context, state) =>
                StoreProfileEditScreen(merchant: state.extra as Merchant),
          ),
          GoRoute(
            path: '/settings/branches/:id',
            builder: (context, state) =>
                BranchEditScreen(branch: state.extra as Branch),
          ),
          GoRoute(
            path: '/settings/branches/:id/hours',
            builder: (context, state) => BranchHoursScreen(
              branchId: state.pathParameters['id']!,
              branchName: state.extra as String,
            ),
          ),
        ],
      ),
    ],
  );
});
