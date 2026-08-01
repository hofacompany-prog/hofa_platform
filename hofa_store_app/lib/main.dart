import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/env.dart';
import 'core/push_service.dart';
import 'router.dart';

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
    // app vẫn chạy bình thường, chỉ không nhận được push khi có đơn mới. Xem README.md.
    debugPrint('[push] Firebase chưa sẵn sàng, bỏ qua push notification: $e');
  }

  runApp(const ProviderScope(child: HofaStoreApp()));
}

class HofaStoreApp extends ConsumerWidget {
  const HofaStoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HOFA — Quản lý cửa hàng',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
