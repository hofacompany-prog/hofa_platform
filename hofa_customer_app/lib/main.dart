import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/app_update_service.dart';
import 'core/deep_link_service.dart';
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
    debugPrint('[boot] Bắt đầu Firebase.initializeApp...');
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
    debugPrint('[boot] Firebase.initializeApp xong, bắt đầu PushService.init...');
    await PushService.instance.init(navigatorKey).timeout(const Duration(seconds: 8));
    debugPrint('[boot] PushService.init xong.');
  } catch (e) {
    // Chưa cấu hình Firebase (thiếu google-services.json / GoogleService-Info.plist) hoặc bước
    // nào đó quá 8s (vd requestPermission() kẹt chờ popup hệ thống không hiện được) — bỏ qua,
    // app vẫn phải vào được màn chính, chỉ mất tính năng push, không được phép treo trắng màn
    // hình vĩnh viễn. Xem README.md.
    debugPrint('[push] Firebase/push chưa sẵn sàng, bỏ qua: $e');
  }

  debugPrint('[boot] Chuẩn bị runApp()...');
  runApp(const ProviderScope(child: HofaCustomerApp()));
}

class HofaCustomerApp extends ConsumerStatefulWidget {
  const HofaCustomerApp({super.key});

  @override
  ConsumerState<HofaCustomerApp> createState() => _HofaCustomerAppState();
}

class _HofaCustomerAppState extends ConsumerState<HofaCustomerApp> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPwaVersion());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNativeUpdate());
      // Link "Chia sẻ cửa hàng" mở thẳng app (Universal Links/App Links + custom scheme dự
      // phòng) — xem core/deep_link_service.dart.
      DeepLinkService.instance.init(ref.read(routerProvider));
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) DeepLinkService.instance.dispose();
    super.dispose();
  }

  Future<void> _checkPwaVersion() async {
    // Chạy mỗi lần mở app — logic so sánh + hiện popup dùng chung với nút "Kiểm tra cập nhật"
    // ở màn Tài khoản, xem PwaVersionService.checkForUpdate.
    if (!mounted) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await PwaVersionService.checkForUpdate(context);
  }

  // Bản cài từ CH Play/App Store (không phải PWA) — ép cập nhật riêng qua
  // AppUpdateService, xem core/app_update_service.dart.
  Future<void> _checkNativeUpdate() async {
    if (!mounted) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await AppUpdateService.checkForUpdate(context);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HOFA',
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
