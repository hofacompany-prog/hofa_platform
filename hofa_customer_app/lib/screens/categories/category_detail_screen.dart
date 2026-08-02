import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/product_card.dart';

/// Mở khi bấm 1 danh mục gốc: hiện danh mục con (2 hàng + "Xem tất cả") trước, sản
/// phẩm nổi bật của danh mục này bên dưới. Bấm vào 1 danh mục con mới sang danh sách
/// sản phẩm đầy đủ (CategoryProductsScreen) — đúng luồng 2 bước khách yêu cầu.
class CategoryDetailScreen extends ConsumerWidget {
  final String categoryId;
  final String? categoryName;

  const CategoryDetailScreen({super.key, required this.categoryId, this.categoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final featuredAsync = ref.watch(categoryFeaturedProductsProvider(categoryId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(categoryName ?? 'Danh mục'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Lỗi: $e'),
            data: (categories) {
              final children = categories.where((c) => c.parentId == categoryId).toList();
              if (children.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Danh mục con', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  CategoryGrid(
                    categories: children,
                    onTapCategory: (c) => context.push('/categories/${c.id}/products', extra: c.name),
                    onTapViewAll: () => context.push('/categories/$categoryId/children', extra: categoryName),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
          Text('Sản phẩm nổi bật', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          featuredAsync.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Lỗi: $e'),
            data: (products) {
              if (products.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: Text('Chưa có sản phẩm nổi bật trong danh mục này'),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemBuilder: (context, i) {
                  final p = products[i];
                  return ProductCard(product: p, onTap: () => context.push('/products/${p.id}'));
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
