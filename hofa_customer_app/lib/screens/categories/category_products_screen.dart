import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/product_card.dart';

/// Sản phẩm thuộc 1 danh mục, gộp từ mọi cửa hàng — mở khi bấm icon danh mục ở trang chủ
/// hoặc từ màn "Tất cả danh mục".
class CategoryProductsScreen extends ConsumerWidget {
  final String categoryId;
  final String? categoryName;

  const CategoryProductsScreen({super.key, required this.categoryId, this.categoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(categoryProductsProvider(categoryId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(categoryName ?? 'Danh mục'),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (products) {
          if (products.isEmpty) return const Center(child: Text('Chưa có sản phẩm nào trong danh mục này'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
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
    );
  }
}
