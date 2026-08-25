import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/product_card.dart';

/// Sản phẩm thuộc 1 danh mục, gộp từ mọi cửa hàng — mở khi bấm icon danh mục ở trang chủ
/// hoặc từ màn "Tất cả danh mục". Tải dần theo trang khi khách lướt gần tới cuối (xem
/// categoryProductsPagedProvider), không tải hết 1 lần.
class CategoryProductsScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final String? categoryName;

  const CategoryProductsScreen({super.key, required this.categoryId, this.categoryName});

  @override
  ConsumerState<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends ConsumerState<CategoryProductsScreen> {
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
      ref.read(categoryProductsPagedProvider(widget.categoryId).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoryProductsPagedProvider(widget.categoryId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(widget.categoryName ?? 'Danh mục'),
      ),
      body: state.isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.items.isEmpty
              ? Center(child: Text('Lỗi: ${state.error}'))
              : state.items.isEmpty
                  ? const Center(child: Text('Chưa có sản phẩm nào trong danh mục này'))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: state.items.length + (state.hasMore ? 1 : 0),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.54,
                      ),
                      itemBuilder: (context, i) {
                        if (i == state.items.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final p = state.items[i];
                        return ProductCard(product: p, onTap: () => context.push('/products/${p.id}'));
                      },
                    ),
    );
  }
}
