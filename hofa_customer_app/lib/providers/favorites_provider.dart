import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/paginated_list_notifier.dart';
import '../models/merchant.dart';
import '../repositories/favorite_repository.dart';

final favoriteRepoProvider = Provider((ref) => FavoriteRepository());

/// Danh sách id cửa hàng khách đã yêu thích — dùng để tô/tắt icon tim ở MerchantCard/
/// merchant_detail_screen.dart mà không phải chờ tải lại mỗi lần chuyển màn. [toggle] cập
/// nhật state NGAY (optimistic) trước khi gọi API, rồi tự lùi lại nếu API lỗi — bấm tim phải
/// phản hồi tức thì, không đợi round-trip mạng.
class FavoriteIdsNotifier extends StateNotifier<AsyncValue<Set<String>>> {
  FavoriteIdsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  final FavoriteRepository _repo;

  Future<void> _load() async {
    try {
      final ids = await _repo.ids();
      state = AsyncValue.data(ids);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<void> toggle(String merchantId) async {
    final current = Set<String>.from(state.valueOrNull ?? const <String>{});
    final wasFavorite = current.contains(merchantId);
    final optimistic = Set<String>.from(current);
    if (wasFavorite) {
      optimistic.remove(merchantId);
    } else {
      optimistic.add(merchantId);
    }
    state = AsyncValue.data(optimistic);
    try {
      if (wasFavorite) {
        await _repo.remove(merchantId);
      } else {
        await _repo.add(merchantId);
      }
    } catch (_) {
      // Lỗi mạng/API — trả lại đúng trạng thái trước khi bấm, không để icon tim "nói dối".
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

final favoriteIdsProvider =
    StateNotifierProvider<FavoriteIdsNotifier, AsyncValue<Set<String>>>(
      (ref) => FavoriteIdsNotifier(ref.watch(favoriteRepoProvider)),
    );

/// Danh sách đầy đủ (tên, ảnh, rating...) cho màn "Cửa hàng yêu thích" — tải dần theo trang.
final favoriteMerchantsPagedProvider =
    StateNotifierProvider.autoDispose<
      PaginatedListNotifier<Merchant>,
      PaginatedState<Merchant>
    >(
      (ref) => PaginatedListNotifier<Merchant>(
        (limit, offset) =>
            ref.read(favoriteRepoProvider).list(limit: limit, offset: offset),
      ),
    );
