import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_exception.dart';
import '../models/user_profile.dart';
import '../models/driver.dart';
import '../repositories/user_repository.dart';
import '../repositories/driver_repository.dart';

final _userRepo = UserRepository();
final _driverRepo = DriverRepository();

/// Phát lại mỗi khi trạng thái đăng nhập Supabase đổi (login/logout/token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentSessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  return auth?.session ?? Supabase.instance.client.auth.currentSession;
});

/// Hồ sơ public.users — null nếu đã đăng nhập Supabase nhưng chưa gọi auth.syncProfile.
final userProfileProvider = FutureProvider.autoDispose<UserProfile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  try {
    return await _userRepo.me();
  } on ApiException catch (e) {
    if (e.code == 'PROFILE_NOT_FOUND') return null;
    rethrow;
  }
});

/// Hồ sơ tài xế của user hiện tại — null nếu chưa đăng ký làm tài xế.
final myDriverProvider = FutureProvider.autoDispose<Driver?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  if (profile == null) return null;
  return _driverRepo.me();
});
