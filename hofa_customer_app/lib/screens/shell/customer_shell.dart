import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/pwa_install_service.dart';
import '../../core/require_login.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/install_pwa_dialog.dart';
import '../../widgets/tab_icon.dart';

/// Cờ toàn app (KHÔNG phải field trong State) — chặn 2 popup nhắc cài PWA chồng nhau tuyệt đối,
/// kể cả trong trường hợp hiếm CustomerShell bị tạo lại (dispose/initState lại) đúng lúc dialog
/// cũ chưa kịp đóng, field trong State cũ sẽ mất theo State đó nhưng biến module-level này thì
/// không.
bool _pwaReminderShowing = false;

class CustomerShell extends ConsumerStatefulWidget {
  final Widget child;
  const CustomerShell({super.key, required this.child});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  Timer? _reminderTimer;

  static const _items = [
    (
      tabKey: 'home',
      icon: Icons.storefront_outlined,
      selected: Icons.storefront,
      label: 'Trang chủ',
      path: '/',
    ),
    (
      tabKey: 'cart',
      icon: Icons.shopping_cart_outlined,
      selected: Icons.shopping_cart,
      label: 'Giỏ hàng',
      path: '/cart',
    ),
    (
      tabKey: 'preorder',
      icon: Icons.event_repeat_outlined,
      selected: Icons.event_repeat,
      label: 'Đặt trước',
      path: '/preorder',
    ),
    (
      tabKey: 'orders',
      icon: Icons.receipt_long_outlined,
      selected: Icons.receipt_long,
      label: 'Đơn hàng',
      path: '/orders',
    ),
    (
      tabKey: 'profile',
      icon: Icons.person_outline,
      selected: Icons.person,
      label: 'Tài khoản',
      path: '/profile',
    ),
  ];

  int _indexFor(String location) {
    if (location == '/') return 0;
    if (location.startsWith('/merchants') || location.startsWith('/products'))
      return 0;
    if (location.startsWith('/checkout')) return 1;
    final i = _items.indexWhere(
      (d) => d.path != '/' && location.startsWith(d.path),
    );
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _startReminderTimer();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  /// Đợi tải chu kỳ (phút) admin cấu hình (hofa-db/88_pwa_reminder_settings.sql) rồi hẹn giờ
  /// nhắc lặp lại suốt phiên app — CustomerShell bọc TOÀN BỘ route trong ShellRoute nên đúng
  /// nghĩa "nhắc khi khách đang ở bất kỳ trang nào của Hofa", không chỉ 1 trang cụ thể.
  Future<void> _startReminderTimer() async {
    final minutes = await ref.read(pwaReminderIntervalMinutesProvider.future);
    if (!mounted) return;
    _reminderTimer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => _maybeShowReminder(),
    );
  }

  void _maybeShowReminder() {
    if (!mounted || _pwaReminderShowing) return;
    // Đang có popup/dialog KHÁC hiện trên cùng route (vd "Đăng nhập để tiếp tục", "Quên mật
    // khẩu") thì route hiện tại của chính CustomerShell không còn isCurrent — bỏ qua lượt này,
    // đợi chu kỳ sau, tránh 2 popup chồng nhau.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    // Đã cài rồi (dù đang mở lại bằng trình duyệt thường) thì thôi hẳn, không nhắc nữa — khác
    // InstallPwaScreen trước đây (vẫn nhắc "mở app ở màn hình chính" kể cả đã cài).
    final needsInstall =
        !PwaInstallService.isStandalone() &&
        !PwaInstallService.wasInstalledPreviously() &&
        (PwaInstallService.hasDeferredPrompt() || PwaInstallService.isIOS());
    if (!needsInstall) return;
    final location = GoRouterState.of(context).matchedLocation;
    if (location == '/login' || location == '/complete-profile') return;
    _pwaReminderShowing = true;
    showInstallPwaDialog(context).whenComplete(() {
      _pwaReminderShowing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(location);
    final cart = ref.watch(cartProvider);
    final instantCount = cart.salesModel == 'instant' ? cart.itemCount : 0;
    final preorderCount = cart.salesModel == 'scheduled' ? cart.itemCount : 0;
    final iconByTabKey = ref.watch(navIconsProvider).valueOrNull ?? const {};
    // Watch ở đây (bọc TOÀN BỘ route) CHỈ để side effect BadgeService.set() (badge icon app)
    // tự đồng bộ đúng số thông báo "Đơn hàng" chưa đọc — xem app_providers.dart.
    ref.watch(unreadOrderCountProvider);

    return Scaffold(
      body: widget.child,
      // onlyShowSelected: chỉ hiện chữ cho mục đang chọn (giống store app) — 5 mục hiện đủ
      // chữ cùng lúc trên màn hẹp dễ bị dính/chật, ẩn bớt chữ mục chưa chọn cho gọn gàng.
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          // "Đơn hàng"/"Tài khoản" cần đăng nhập — hỏi bằng popup trước khi chuyển tab, các tab
          // còn lại (Trang chủ/Giỏ hàng/Đặt trước) xem tự do (xem require_login.dart).
          onDestinationSelected: (i) async {
            final path = _items[i].path;
            if ((path == '/orders' || path == '/profile') &&
                !await requireLogin(context)) {
              return;
            }
            if (context.mounted) context.go(path);
          },
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: _items.map((d) {
            final count = d.label == 'Giỏ hàng'
                ? instantCount
                : d.label == 'Đặt trước'
                ? preorderCount
                : 0;
            final iconUrl = iconByTabKey[d.tabKey];
            final unselected = TabIcon(
              url: iconUrl,
              fallback: d.icon,
              color: theme.colorScheme.outline,
              size: 22,
            );
            final selected = TabIcon(
              url: iconUrl,
              fallback: d.selected,
              color: theme.colorScheme.primary,
              size: 22,
            );
            return NavigationDestination(
              icon: count > 0
                  ? Badge(label: Text('$count'), child: unselected)
                  : unselected,
              selectedIcon: count > 0
                  ? Badge(label: Text('$count'), child: selected)
                  : selected,
              label: d.label,
            );
          }).toList(),
        ),
      ),
    );
  }
}
