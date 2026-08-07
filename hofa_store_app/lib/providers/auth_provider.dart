import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_exception.dart';
import '../models/user_profile.dart';
import '../models/merchant.dart';
import '../models/merchant_today_stats.dart';
import '../models/finance_summary.dart';
import '../models/product.dart';
import '../models/auto_accept_settings.dart';
import '../repositories/user_repository.dart';
import '../repositories/merchant_repository.dart';

final _userRepo = UserRepository();
final _merchantRepo = MerchantRepository();

/// Họ tên + SĐT vừa nhập lúc đăng ký (OTP xác nhận xong) — chỉ giữ tạm trong bộ nhớ để
/// điền sẵn màn "Tạo cửa hàng" tiếp theo, KHÔNG ghi xuống database ở bước này. Hồ sơ
/// public.users thật sự chỉ được tạo khi chủ cửa hàng hoàn tất "Tạo cửa hàng" (xem
/// CreateStoreScreen._submit) — bỏ dở giữa chừng thì không có gì bị lưu lại.
class PendingSignup {
  final String fullName;
  final String phone;
  const PendingSignup({required this.fullName, required this.phone});
}

final pendingSignupProvider = StateProvider<PendingSignup?>((ref) => null);

/// Sản phẩm vừa được "sao chép" (xem CopiedProduct) — dùng để "dán" lại lúc tạo sản phẩm
/// mới tương tự ở bất kỳ đâu trong app.
final copiedProductProvider = StateProvider<CopiedProduct?>((ref) => null);

/// Phát lại mỗi khi trạng thái đăng nhập Supabase đổi (login/logout/token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentSessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  return auth?.session ?? Supabase.instance.client.auth.currentSession;
});

/// Hồ sơ public.users — null nếu đã đăng nhập Supabase nhưng chưa gọi auth.syncProfile.
final userProfileProvider = FutureProvider.autoDispose<UserProfile?>((
  ref,
) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  try {
    return await _userRepo.me();
  } on ApiException catch (e) {
    if (e.code == 'PROFILE_NOT_FOUND') return null;
    rethrow;
  }
});

/// Cửa hàng của user hiện tại — null nếu chưa tạo cửa hàng.
final myMerchantProvider = FutureProvider.autoDispose<Merchant?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  if (profile == null) return null;
  return _merchantRepo.myMerchant();
});

/// Số liệu nhanh (đơn đang chuẩn bị, thu nhập/số đơn hôm nay) cho màn Trang chủ.
final merchantTodayStatsProvider = FutureProvider.autoDispose<MerchantTodayStats?>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return null;
  return _merchantRepo.todayStats(merchant.id);
});

/// Tóm tắt tài chính theo period ('today'/'yesterday'/'week') — dùng cho card "Thu nhập hôm
/// nay" ở Trang chủ (luôn gọi với 'today') và tab Tóm tắt ở màn Tài chính.
final financeSummaryProvider = FutureProvider.autoDispose
    .family<FinanceSummary?, String>((ref, period) async {
      final merchant = await ref.watch(myMerchantProvider.future);
      if (merchant == null) return null;
      return _merchantRepo.financeSummary(merchant.id, period: period);
    });

/// Tham số toàn sàn cho "Tự động nhận đơn" (admin cấu hình) — dùng ở màn nhận đơn để tính trần
/// thời gian chuẩn bị và hiện đúng kiểu đếm ngược theo chế độ của chi nhánh.
final autoAcceptSettingsProvider = FutureProvider.autoDispose<AutoAcceptSettings>(
  (ref) => _merchantRepo.autoAcceptSettings(),
);
