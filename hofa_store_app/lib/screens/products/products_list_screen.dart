import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';

final _productsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return ProductRepository().list(merchant.id);
});

final _toppingGroupsProvider = FutureProvider.autoDispose<List<ToppingGroup>>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return ProductRepository().merchantToppingGroups(merchant.id);
});

const _statusLabels = {
  'draft': 'Nháp',
  'active': 'Đang bán',
  'out_of_stock': 'Hết hàng',
  'hidden': 'Đã ẩn',
  'archived': 'Đã xoá',
};

final _repo = ProductRepository();

Future<void> _toggleActive(
  BuildContext context,
  WidgetRef ref,
  Product p,
) async {
  final newStatus = p.status == 'active' ? 'hidden' : 'active';
  try {
    await _repo.update(p.id, {'status': newStatus});
    ref.invalidate(_productsProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

Future<void> _confirmDeleteToppingGroup(
  BuildContext context,
  WidgetRef ref,
  ToppingGroup g,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá nhóm topping?'),
      content: Text(
        g.linkedProductCount > 0
            ? 'Xoá nhóm "${g.name}" sẽ gỡ luôn khỏi ${g.linkedProductCount} sản phẩm đang dùng nhóm này.'
            : 'Xoá nhóm "${g.name}"?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await _repo.deleteToppingGroup(g.id);
    ref.invalidate(_toppingGroupsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã xoá "${g.name}"')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Product p,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá sản phẩm?'),
      content: Text(
        'Xoá "${p.name}"? Sản phẩm sẽ không còn hiển thị nữa, đơn hàng cũ vẫn giữ nguyên thông tin.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await _repo.delete(p.id);
    ref.invalidate(_productsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã xoá "${p.name}"')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

class ProductsListScreen extends ConsumerWidget {
  const ProductsListScreen({super.key});

  Widget _productCard(BuildContext context, WidgetRef ref, Product p) {
    final isActive = p.status == 'active';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/products/${p.id}/edit'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Opacity(
                opacity: isActive ? 1 : 0.5,
                child: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  backgroundImage: p.images.isNotEmpty
                      ? NetworkImage(p.images.first)
                      : null,
                  child: p.images.isEmpty
                      ? const Icon(Icons.storefront, color: Colors.green)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Opacity(
                  opacity: isActive ? 1 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.variants.isEmpty
                            ? 'Chưa có biến thể/giá — bấm để thêm'
                            : '${p.variants.length} biến thể · từ ${formatVnd(p.lowestPrice)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          label: Text(_statusLabels[p.status] ?? p.status),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Switch(
                value: isActive,
                onChanged: (_) => _toggleActive(context, ref, p),
              ),
              IconButton(
                tooltip: 'Xoá sản phẩm',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, p),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toppingGroupCard(
    BuildContext context,
    WidgetRef ref,
    ToppingGroup g,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/topping-groups/${g.id}/edit'),
        title: Text(g.name),
        subtitle: Text(
          g.linkedProductCount > 0
              ? 'Đã liên kết với ${g.linkedProductCount} món'
              : 'Chưa liên kết sản phẩm nào',
        ),
        trailing: IconButton(
          tooltip: 'Xoá nhóm topping',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDeleteToppingGroup(context, ref, g),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(_productsProvider);
    final toppingGroupsAsync = ref.watch(_toppingGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sản phẩm'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/topping-groups/new'),
              icon: const Icon(Icons.add),
              label: const Text('Thêm topping'),
            ),
          ),
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_productsProvider);
          ref.invalidate(_toppingGroupsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            productsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Lỗi tải sản phẩm: $e'),
              data: (products) {
                if (products.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
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
                return Column(
                  children: [
                    for (final p in products) ...[
                      _productCard(context, ref, p),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Nhóm topping',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tạo 1 lần rồi gắn vào nhiều sản phẩm — sửa ở phần "Tạo/sửa sản phẩm".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            toppingGroupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Lỗi tải nhóm topping: $e'),
              data: (groups) => groups.isEmpty
                  ? const Text('Chưa có nhóm topping nào.')
                  : Column(
                      children: groups
                          .map((g) => _toppingGroupCard(context, ref, g))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
