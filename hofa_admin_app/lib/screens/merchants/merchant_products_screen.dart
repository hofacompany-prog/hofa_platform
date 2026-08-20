import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/merchant.dart';
import '../../models/product.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

/// Danh sách sản phẩm của 1 cửa hàng — admin xem/sửa đầy đủ như chính cửa hàng đó tự quản lý
/// (xem hofa_store_app/lib/screens/products/products_list_screen.dart, bản gốc). Nhóm topping
/// không lặp lại ở đây — đã có sẵn merchant_topping_groups_card.dart trong màn chi tiết cửa
/// hàng, sản phẩm chỉ cần GẮN vào nhóm có sẵn (xem merchant_product_form_screen.dart).
class MerchantProductsScreen extends ConsumerWidget {
  final Merchant merchant;
  const MerchantProductsScreen({super.key, required this.merchant});

  Future<void> _toggleActive(BuildContext context, WidgetRef ref, Product p) async {
    final newStatus = p.status == 'active' ? 'hidden' : 'active';
    try {
      await ref.read(adminRepoProvider).updateProduct(p.id, {'status': newStatus});
      ref.invalidate(merchantProductsProvider(merchant.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _quickEditPrice(BuildContext context, WidgetRef ref, Product p) async {
    if (p.variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sản phẩm chưa có biến thể/giá để sửa')),
      );
      return;
    }
    final controllers = {
      for (final v in p.variants)
        v.id: TextEditingController(text: VndInputFormatter.display(v.price)),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa giá nhanh'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in p.variants) ...[
                TextField(
                  controller: controllers[v.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [VndInputFormatter()],
                  decoration: InputDecoration(
                    labelText: p.variants.length > 1 ? v.name : 'Giá (đ)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (v != p.variants.last) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;

    final changed = p.variants.where((v) {
      final newPrice = VndInputFormatter.parse(controllers[v.id]!.text);
      return newPrice != null && newPrice != v.price;
    }).toList();
    if (changed.isEmpty) return;

    try {
      await Future.wait(
        changed.map(
          (v) => ref.read(adminRepoProvider).updateVariant(v.id, {
            'price': VndInputFormatter.parse(controllers[v.id]!.text),
          }),
        ),
      );
      ref.invalidate(merchantProductsProvider(merchant.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật giá')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<Product> products,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<Product>.from(products);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          await ref.read(adminRepoProvider).updateProduct(reordered[i].id, {'sort_order': i});
        }
      }
      ref.invalidate(merchantProductsProvider(merchant.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Product p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá sản phẩm?'),
        content: Text(
          'Xoá "${p.name}"? Sản phẩm sẽ không còn hiển thị nữa, đơn hàng cũ vẫn giữ nguyên thông tin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(adminRepoProvider).deleteProduct(p.id);
      ref.invalidate(merchantProductsProvider(merchant.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xoá "${p.name}"')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Widget _productCard(BuildContext context, WidgetRef ref, Product p, int index) {
    final isActive = p.status == 'active';
    return Card(
      key: ValueKey(p.id),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          '/merchants/${merchant.id}/products/${p.id}/edit',
          extra: merchant,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Opacity(
                opacity: isActive ? 1 : 0.5,
                child: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  backgroundImage: p.images.isNotEmpty ? NetworkImage(p.images.first) : null,
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
                      Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      if (p.variants.isEmpty)
                        Text(
                          'Chưa có biến thể/giá — bấm để thêm',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _quickEditPrice(context, ref, p),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${p.variants.length} biến thể',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'từ ${formatVnd(p.lowestPrice)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nút bật/tắt + kéo sắp xếp cùng 1 hàng — dồn xuống hàng dưới (cùng nút
                  // xoá) từng bị chèn sát khu vực "sửa giá nhanh" ở cột bên trái.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: isActive,
                          onChanged: (_) => _toggleActive(context, ref, p),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Xoá sản phẩm',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, ref, p),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(merchantProductsProvider(merchant.id));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/merchants/${merchant.id}'),
        ),
        title: Text('Menu — ${merchant.name}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(merchantProductsProvider(merchant.id)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.push(
                  '/merchants/${merchant.id}/products/new',
                  extra: merchant,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Thêm sản phẩm'),
              ),
            ),
            const SizedBox(height: 16),
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
                        const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Chưa có sản phẩm nào'),
                      ],
                    ),
                  );
                }
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: products.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _reorder(context, ref, products, oldIndex, newIndex),
                  itemBuilder: (context, index) => Padding(
                    key: ValueKey('pad-${products[index].id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _productCard(context, ref, products[index], index),
                  ),
                );
              },
            ),
            if (productsAsync.valueOrNull?.isNotEmpty ?? false) ...[
              const SizedBox(height: 16),
              StatCard(
                label: 'Tổng sản phẩm',
                value: '${productsAsync.valueOrNull!.length}',
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
