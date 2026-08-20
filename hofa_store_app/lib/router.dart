import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'core/pwa_install_service.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/install/install_pwa_screen.dart';
import 'screens/onboarding/create_store_screen.dart';
import 'screens/dashboard/dashboard_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/products/products_list_screen.dart';
import 'screens/products/product_form_screen.dart';
import 'screens/toppings/topping_group_form_screen.dart';
import 'screens/orders/orders_list_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/orders/chat_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/settings/branch_settings_screen.dart';
import 'screens/settings/store_profile_edit_screen.dart';
import 'screens/settings/branch_edit_screen.dart';
import 'screens/settings/branch_hours_screen.dart';
import 'screens/settings/devices_screen.dart';
import 'screens/settings/staff_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'models/merchant.dart';
import 'models/branch.dart';
import 'main.dart' show navigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    // initialLocation cố định ('/home') từng khiến app LUÔN boot ở trang chủ bất kể trình
    // duyệt/PWA thực sự mở ở URL nào — kể cả khi service worker đã điều hướng
    // clients.openWindow()/client.navigate() đúng tới /orders/:id lúc bấm push (xem
    // web/firebase-messaging-sw.js), route đó vẫn bị initialLocation ghi đè ngay khi
    // GoRouter khởi tạo. Trên web, ưu tiên URL thật của trình duyệt lúc mở app; '/home' chỉ
    // còn là dự phòng khi URL rỗng/gốc hoặc trên mobile (không có khái niệm URL).
    initialLocation: kIsWeb && Uri.base.path.length > 1
        ? Uri.base.path
        : '/home',
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
      if (state.matchedLocation == '/install-pwa') return '/home';

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
      GoRoute(
        path: '/install-pwa',
        builder: (context, state) => const InstallPwaScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const CreateStoreScreen(),
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
            // Truy cập CHỈ qua nút trong chi tiết đơn, không có hộp thư riêng — xem
            // hofa-db/74_order_chat.sql.
            path: '/orders/:id/chat',
            builder: (context, state) =>
                ChatScreen(orderId: state.pathParameters['id']!),
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
            path: '/settings/staff',
            builder: (context, state) => const StaffScreen(),
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
