import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'router.dart';
import 'widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  runApp(const ProviderScope(child: HofaAdminApp()));
}

class HofaAdminApp extends ConsumerWidget {
  const HofaAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'HOFA Admin',
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
