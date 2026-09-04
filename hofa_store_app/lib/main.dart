import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/app_update_service.dart';
import 'core/env.dart';
import 'core/push_service.dart';
import 'core/pwa_version_service.dart';
import 'router.dart';
import 'widgets/app_background.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  try {
    await Firebase.initializeApp(
      options: kIsWeb
          ? FirebaseOptions(
              apiKey: Env.firebaseApiKey,
              authDomain: Env.firebaseAuthDomain,
              projectId: Env.firebaseProjectId,
              storageBucket: Env.firebaseStorageBucket,
              messagingSenderId: Env.firebaseMessagingSenderId,
              appId: Env.firebaseAppId,
            )
          : null,
    ).timeout(const Duration(seconds: 8));
    await PushService.instance.init(navigatorKey).timeout(const Duration(seconds: 8));
  } catch (e) {
    // Chưa cấu hình Firebase (thiếu google-services.json / GoogleService-Info.plist) hoặc bước
    // nào đó quá 8s (vd chờ mạng/APNs kẹt) — bỏ qua, app vẫn phải vào được màn chính, chỉ mất
    // tính năng push, không được phép treo trắng màn hình vĩnh viễn. Xem README.md.
    debugPrint('[push] Firebase chưa sẵn sàng, bỏ qua push notification: $e');
  }

  runApp(const ProviderScope(child: HofaStoreApp()));
}

class HofaStoreApp extends ConsumerStatefulWidget {
  const HofaStoreApp({super.key});

  @override
  ConsumerState<HofaStoreApp> createState() => _HofaStoreAppState();
}

class _HofaStoreAppState extends ConsumerState<HofaStoreApp> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPwaVersion());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNativeUpdate());
    }
  }

  // Bản cài từ CH Play/App Store (không phải PWA) — ép cập nhật riêng qua
  // AppUpdateService, xem core/app_update_service.dart.
  Future<void> _checkNativeUpdate() async {
    if (!mounted) return;
    // navigatorKey.currentContext thường vẫn null ngay lúc khung hình đầu tiên vừa vẽ xong
    // (Navigator của MaterialApp.router chưa kịp gắn) — xác nhận qua debug thật, khiến bước
    // kiểm tra ép cập nhật bị bỏ qua âm thầm mỗi lần. Thử lại tối đa 4s thay vì bỏ cuộc ngay.
    BuildContext? context = navigatorKey.currentContext;
    for (var i = 0; context == null && i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      context = navigatorKey.currentContext;
    }
    if (context == null || !context.mounted) return;
    await AppUpdateService.checkForUpdate(context);
  }

  Future<void> _checkPwaVersion() async {
    // Chạy mỗi lần mở app, không chờ phát hiện lệch version — xem lý do ở
    // pwa_version_service_web.dart#unregisterStaleServiceWorkers.
    PwaVersionService.unregisterStaleServiceWorkers().catchError((_) {});
    final deployedVersion = await PwaVersionService.fetchDeployedVersion();
    if (!mounted || deployedVersion == null) return;
    if (deployedVersion == Env.appVersion) return;

    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Đã có phiên bản mới'),
        content: Text(
          'Phiên bản $deployedVersion đã sẵn sàng. Cập nhật để tải dữ liệu và giao diện mới nhất.',
        ),
        actions: [
          FilledButton(
            onPressed: PwaVersionService.clearCacheAndReload,
            child: const Text('Cập nhật ngay'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HOFA — Quản lý cửa hàng',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF85C100),
          primary: const Color(0xFF85C100),
          secondary: const Color(0xFFFB8519),
        ),
        useMaterial3: true,
        fontFamily: 'Montserrat',
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
        ),
      ),
      builder: (context, child) => AppBackground(child: child!),
      routerConfig: router,
    );
  }
}
