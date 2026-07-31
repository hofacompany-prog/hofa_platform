import 'dart:async';
import 'package:flutter/foundation.dart';

/// Biến 1 Stream thành Listenable để GoRouter tự redirect lại mỗi khi
/// trạng thái đăng nhập Supabase đổi (login/logout/token refresh).
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
