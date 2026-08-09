import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/nav_icon_repository.dart';

final navIconRepoProvider = Provider((ref) => NavIconRepository());

/// Icon tabbar tuỳ chỉnh — không cần đăng nhập, lỗi mạng tự trả về map rỗng (xem
/// NavIconRepository), không chặn khởi động app.
final navIconsProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(navIconRepoProvider).navIcons(),
);
