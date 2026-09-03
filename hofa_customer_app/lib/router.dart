import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/go_router_refresh_stream.dart';
import 'providers/auth_providers.dart';
import 'providers/app_providers.dart' show merchantRepoProvider;
import 'screens/auth/login_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/shell/customer_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/merchant/merchant_detail_screen.dart';
import 'screens/merchant/merchant_reviews_screen.dart';
import 'screens/merchant/report_price_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/preorder/preorder_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'models/preorder_schedule.dart';
import 'models/buy_now_request.dart';
import 'screens/orders/orders_list_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/orders/chat_screen.dart';
import 'models/chat_message.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/categories/all_categories_screen.dart';
import 'screens/categories/category_detail_screen.dart';
import 'screens/categories/category_products_screen.dart';
import 'screens/favorites/favorite_merchants_screen.dart';
import 'main.dart' show navigatorKey;

final _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _merchantSlugPathRe = RegExp(r'^/merchants/([^/]+)(/reviews)?$');

/// Chuyển tab (5 mục ở thanh điều hướng dưới CustomerShell) không hiệu ứng — trượt/push mặc
/// định của go_router hợp khi ĐI SÂU vào 1 màn con (vd mở chi tiết cửa hàng), nhưng chuyển tab
/// ngang hàng thì không phải "đi vào" đâu cả nên trông giật. Từng thử fade nhưng 2 trang cùng
/// mờ dần chồng lên nhau giữa chừng làm chữ 2 trang nhìn xuyên/chồng lên nhau — đổi hẳn sang
/// không hiệu ứng (tức thì) giống cách phần lớn app thật xử lý chuyển tab gốc (Instagram,
/// Facebook...), vừa mượt vừa không còn lỗi chồng chữ. Chỉ áp dụng cho đúng 5 route gốc này,
/// các route con (merchant/product detail, checkout...) vẫn giữ nguyên hiệu ứng trượt mặc định.
Page<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

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
      // Link chia sẻ cửa hàng (nút "Chia sẻ cửa hàng" ở merchant_detail_screen.dart) dùng slug
      // (tên đọc được) thay vì UUID cho dễ đọc — GET /merchants/:id đã hỗ trợ tra bằng slug
      // (server/src/routes/merchants.js). MerchantDetailScreen bên dưới vẫn luôn cần UUID thật
      // làm khoá cho các provider sản phẩm/danh mục/yêu thích, nên thay vì sửa lại toàn bộ
      // luồng bên trong màn hình, chỉ tra slug -> id thật 1 lần ở đây rồi redirect sang URL có
      // UUID thật. Link nội bộ (đã dùng UUID sẵn) khớp _uuidRe nên bỏ qua nhánh này ngay.
      final merchantMatch = _merchantSlugPathRe.firstMatch(state.matchedLocation);
      if (merchantMatch != null && !_uuidRe.hasMatch(merchantMatch.group(1)!)) {
        try {
          final merchant = await ref
              .read(merchantRepoProvider)
              .merchant(merchantMatch.group(1)!)
              .timeout(const Duration(seconds: 8));
          return '/merchants/${merchant.id}${merchantMatch.group(2) ?? ''}';
        } catch (_) {
          return '/';
        }
      }

      // Cài PWA không còn là điều kiện chặn đường đi nữa — khách lướt/đặt hàng/đăng nhập tự do
      // dù chưa cài, chỉ còn popup nhắc định kỳ (xem CustomerShell + widgets/install_pwa_dialog.dart,
      // chu kỳ cấu hình ở admin — hofa-db/88_pwa_reminder_settings.sql).
      final session = Supabase.instance.client.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      final completingProfile = state.matchedLocation == '/complete-profile';

      // Khách chưa đăng nhập lướt TỰ DO hầu hết app (trang chủ, giỏ hàng, đặt trước, chi tiết
      // cửa hàng/sản phẩm, danh mục...) — không còn bị router tự đá sang /login nữa. Chỉ chặn
      // đúng những màn THẬT SỰ cần tài khoản (đặt hàng, đơn hàng, hồ sơ, thông báo, yêu thích).
      // Trải nghiệm CHÍNH là chặn bằng popup "Đăng nhập để tiếp tục" ngay tại nút bấm/tab điều
      // hướng tới các màn này (xem lib/core/require_login.dart, dùng ở cart_screen.dart,
      // product_detail_screen.dart, preorder_screen.dart, merchant_favorite_button.dart,
      // favorites_icon.dart, notification_bell.dart, customer_shell.dart) — TRƯỚC khi điều
      // hướng nên trong luồng dùng bình thường không bao giờ chạm nhánh dưới đây. Nhánh này chỉ
      // là lưới an toàn cho ai gõ thẳng URL/mở deep link, lặng lẽ đưa về trang chủ thay vì hiện
      // màn vỡ vì thiếu đăng nhập (orders/notifications/favorites 401 nhưng không crash — chỉ
      // hiện chữ lỗi xấu; checkout thì chưa xử lý guest, sẽ kẹt lúc đặt đơn).
      const guestProtectedPaths = [
        '/checkout',
        '/orders',
        '/profile',
        '/notifications',
        '/favorites',
      ];
      final isGuestProtected = guestProtectedPaths.any(
        (p) =>
            state.matchedLocation == p ||
            state.matchedLocation.startsWith('$p/'),
      );

      if (session == null) {
        if (loggingIn) return null;
        return isGuestProtected ? '/' : null;
      }

      try {
        // .timeout — không có thì mạng chậm/kẹt sẽ treo redirect() vĩnh viễn, kẹt cả app ở màn
        // trắng (GoRouter chưa quyết định được route đầu tiên) thay vì rơi vào catch bên dưới
        // như ý đồ ban đầu. TimeoutException cũng rơi vào catch (_) như lỗi mạng thường.
        final profile = await ref
            .read(userProfileProvider.future)
            .timeout(const Duration(seconds: 8));
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
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => CustomerShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _tabPage(state, const HomeScreen()),
          ),
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
            path: '/merchants/:id/report-price',
            builder: (context, state) =>
                ReportPriceScreen(merchantId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/cart',
            pageBuilder: (context, state) =>
                _tabPage(state, const CartScreen()),
          ),
          GoRoute(
            path: '/preorder',
            pageBuilder: (context, state) =>
                _tabPage(state, const PreorderScreen()),
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
            pageBuilder: (context, state) =>
                _tabPage(state, const OrdersListScreen()),
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
            // :channel = 'driver' | 'merchant' — xem hofa-db/74_order_chat.sql. Truy cập CHỈ
            // qua nút trong chi tiết đơn, không có hộp thư riêng.
            path: '/orders/:id/chat/:channel',
            builder: (context, state) {
              final isDriver = state.pathParameters['channel'] == 'driver';
              return ChatScreen(
                orderId: state.pathParameters['id']!,
                channel: isDriver
                    ? ChatChannel.customerDriver
                    : ChatChannel.customerMerchant,
                title: isDriver
                    ? 'Nhắn tin với tài xế'
                    : 'Nhắn tin với cửa hàng',
              );
            },
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                _tabPage(state, const ProfileScreen()),
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
