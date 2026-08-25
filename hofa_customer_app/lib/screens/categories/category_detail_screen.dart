import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/product_card.dart';

/// Mở khi bấm 1 danh mục gốc: hiện danh mục con (2 hàng + "Xem tất cả") trước, TOÀN BỘ sản
/// phẩm của danh mục cha này (gộp cả danh mục con, xem server/src/routes/products.js) ngay
/// bên dưới — tải dần theo trang khi khách lướt gần tới cuối trang (scroll-listener gắn vào
/// ListView NGOÀI vì lưới sản phẩm bên trong là shrinkWrap, không tự cuộn được).
class CategoryDetailScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final String? categoryName;

  const CategoryDetailScreen({super.key, required this.categoryId, this.categoryName});

  @override
  ConsumerState<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
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
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsState = ref.watch(categoryProductsPagedProvider(widget.categoryId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(widget.categoryName ?? 'Danh mục'),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Lỗi: $e'),
            data: (categories) {
              final children = categories.where((c) => c.parentId == widget.categoryId).toList();
              if (children.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Danh mục con', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  CategoryGrid(
                    categories: children,
                    onTapCategory: (c) => context.push('/categories/${c.id}/products', extra: c.name),
                    onTapViewAll: () =>
                        context.push('/categories/${widget.categoryId}/children', extra: widget.categoryName),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
          Text('Sản phẩm', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          if (productsState.isInitialLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (productsState.error != null && productsState.items.isEmpty)
            Text('Lỗi: ${productsState.error}')
          else if (productsState.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 12),
              child: Text('Chưa có sản phẩm nào trong danh mục này'),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: productsState.items.length + (productsState.hasMore ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.54,
              ),
              itemBuilder: (context, i) {
                if (i == productsState.items.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final p = productsState.items[i];
                return ProductCard(product: p, onTap: () => context.push('/products/${p.id}'));
              },
            ),
        ],
      ),
    );
  }
}
