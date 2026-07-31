import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';

final _productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return ProductRepository().list(merchant.id);
});

const _statusLabels = {
  'draft': 'Nháp',
  'active': 'Đang bán',
  'out_of_stock': 'Hết hàng',
  'hidden': 'Đã ẩn',
  'archived': 'Đã xoá',
};

class ProductsListScreen extends ConsumerWidget {
  const ProductsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(_productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sản phẩm'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              onPressed: () => context.push('/products/new'),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm'),
            ),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi tải sản phẩm: $e')),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Chưa có sản phẩm nào'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/products/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm sản phẩm đầu tiên'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_productsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = products[i];
                return Card(
                  child: ListTile(
                    onTap: () => context.push('/products/${p.id}/edit'),
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade50,
                      backgroundImage: p.images.isNotEmpty ? NetworkImage(p.images.first) : null,
                      child: p.images.isEmpty ? const Icon(Icons.storefront, color: Colors.green) : null,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.variants.isEmpty
                          ? 'Chưa có biến thể/giá — bấm để thêm'
                          : '${p.variants.length} biến thể · từ ${formatVnd(p.lowestPrice)}',
                    ),
                    trailing: Chip(label: Text(_statusLabels[p.status] ?? p.status)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
