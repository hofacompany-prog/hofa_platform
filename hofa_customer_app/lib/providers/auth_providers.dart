import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_exception.dart';
import '../models/user_profile.dart';
import '../repositories/user_repository.dart';

final userRepoProvider = Provider((ref) => UserRepository());

final authStateProvider = StreamProvider<AuthState>((ref) => Supabase.instance.client.auth.onAuthStateChange);

final currentSessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  return auth?.session ?? Supabase.instance.client.auth.currentSession;
});

/// true trong lúc LoginScreen đang tự đăng ký + đồng bộ hồ sơ (signUp -> /me/sync) — chặn
/// router.dart tự đá qua /complete-profile ngay khi signUp() vừa tạo session (auth state đổi
/// TRƯỚC khi /me/sync kịp chạy xong), tránh bắt nhập lại họ tên/SĐT lần 2 ở màn đó.
final authFlowInProgressProvider = StateProvider<bool>((ref) => false);

/// null = đã đăng nhập Supabase Auth nhưng chưa có hồ sơ public.users (cần /me/sync).
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  try {
    return await ref.watch(userRepoProvider).me();
  } on ApiException catch (e) {
    if (e.code == 'PROFILE_NOT_FOUND') return null;
    rethrow;
  }
});
