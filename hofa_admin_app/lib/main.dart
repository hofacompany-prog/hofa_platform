import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/pwa_version_service.dart';
import 'router.dart';
import 'widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: HofaAdminApp()));
}

class HofaAdminApp extends ConsumerStatefulWidget {
  const HofaAdminApp({super.key});

  @override
  ConsumerState<HofaAdminApp> createState() => _HofaAdminAppState();
}

class _HofaAdminAppState extends ConsumerState<HofaAdminApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPwaVersion());
  }

  Future<void> _checkPwaVersion() async {
    final deployedVersion = await PwaVersionService.fetchDeployedVersion();
    if (!mounted || deployedVersion == null) return;
    if (deployedVersion == Env.appVersion) return;

    final context = adminNavigatorKey.currentContext;
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
