import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/env.dart';
import 'core/push_service.dart';
import 'router.dart';
import 'widgets/app_background.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  try {
    await Firebase.initializeApp();
    await PushService.instance.init(navigatorKey);
  } catch (e) {
    // Chưa cấu hình Firebase (thiếu google-services.json / GoogleService-Info.plist) —
    // app vẫn chạy bình thường, chỉ không nhận được push khi đơn đổi trạng thái. Xem README.md.
    debugPrint('[push] Firebase chưa sẵn sàng, bỏ qua push notification: $e');
  }

  runApp(const ProviderScope(child: HofaCustomerApp()));
}

class HofaCustomerApp extends ConsumerWidget {
  const HofaCustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        appBarTheme: const AppBarTheme(centerTitle: false, backgroundColor: Colors.transparent),
      ),
      builder: (context, child) => AppBackground(child: child!),
      routerConfig: router,
    );
  }
}
