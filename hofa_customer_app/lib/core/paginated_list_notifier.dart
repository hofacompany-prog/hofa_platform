import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trạng thái 1 danh sách tải dần (lazy-load) — [hasMore] tự suy ra từ độ dài trang vừa tải
/// (đúng bằng [PaginatedListNotifier.pageSize] thì coi như còn trang sau, ngắn hơn thì hết),
/// không cần server trả thêm cờ hasMore riêng.
class PaginatedState<T> {
  final List<T> items;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final Object? error;

  const PaginatedState({
    this.items = const [],
    this.hasMore = true,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  PaginatedState<T> copyWith({
    List<T>? items,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error,
  }) => PaginatedState<T>(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: error,
  );
}

/// StateNotifier tải dần 1 danh sách theo trang (limit/offset) — dùng chung cho mọi danh sách
/// dài trong app khách (cửa hàng, sản phẩm theo danh mục/cửa hàng, đơn hàng, thông báo...).
/// [fetchPage] chỉ cần biết cách gọi đúng repository với (limit, offset) tương ứng — notifier
/// tự lo phần trạng thái/nối trang/chặn gọi trùng lúc đang tải.
class PaginatedListNotifier<T> extends StateNotifier<PaginatedState<T>> {
  final Future<List<T>> Function(int limit, int offset) fetchPage;
  final int pageSize;

  PaginatedListNotifier(this.fetchPage, {this.pageSize = 20})
    : super(const PaginatedState()) {
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    state = state.copyWith(isInitialLoading: true, error: null);
    try {
      final page = await fetchPage(pageSize, 0);
      state = PaginatedState<T>(
        items: page,
        hasMore: page.length == pageSize,
        isInitialLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isInitialLoading: false, error: e);
    }
  }

  /// Gọi khi khách lướt gần tới cuối danh sách — không làm gì nếu đang tải dở hoặc đã hết
  /// trang, nên gọi vô tội vạ mỗi lần scroll không cần tự canh trạng thái ở nơi gọi.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isInitialLoading || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await fetchPage(pageSize, state.items.length);
      state = state.copyWith(
        items: [...state.items, ...page],
        hasMore: page.length == pageSize,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  Future<void> refresh() => _loadFirst();
}
