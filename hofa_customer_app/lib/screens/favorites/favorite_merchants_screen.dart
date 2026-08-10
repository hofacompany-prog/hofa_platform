import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/merchant_card.dart';

/// Danh sách cửa hàng khách đã bấm tim yêu thích — mở từ FavoritesIcon ở trang chủ. Tải dần
/// theo trang giống mọi danh sách khác trong app (xem PaginatedListNotifier).
class FavoriteMerchantsScreen extends ConsumerStatefulWidget {
  const FavoriteMerchantsScreen({super.key});

  @override
  ConsumerState<FavoriteMerchantsScreen> createState() =>
      _FavoriteMerchantsScreenState();
}

class _FavoriteMerchantsScreenState
    extends ConsumerState<FavoriteMerchantsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(favoriteMerchantsPagedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(favoriteMerchantsPagedProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Cửa hàng yêu thích'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(favoriteMerchantsPagedProvider);
          await ref.read(favoriteIdsProvider.notifier).refresh();
        },
        child: state.isInitialLoading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.items.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('Lỗi: ${state.error}')),
                  ),
                ],
              )
            : state.items.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có cửa hàng yêu thích nào',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bấm vào biểu tượng trái tim trên thẻ cửa hàng để lưu lại',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: state.items.length + (state.hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final m = state.items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MerchantCard(
                      merchant: m,
                      onTap: () => context.push('/merchants/${m.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
