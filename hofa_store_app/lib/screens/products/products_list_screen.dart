import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';
import '../../widgets/nav_back_button.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/stat_card.dart';

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

/// Chụp lại toàn bộ thông tin sản phẩm (giá, biến thể + bậc giá riêng, nhóm topping đang
/// gắn) vào [copiedProductProvider] để "dán" lại lúc tạo sản phẩm mới tương tự — xem
/// [ProductFormScreen]. Danh sách sản phẩm không kèm sẵn bậc giá/nhóm topping nên phải gọi
/// thêm API lấy chi tiết.
Future<void> _copyProduct(
  BuildContext context,
  WidgetRef ref,
  Product p,
) async {
  try {
    final full = await _repo.get(p.id);
    if (full.variants.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sản phẩm chưa có giá, không thể sao chép'),
          ),
        );
      }
      return;
    }
    final defaultVariant = full.variants.firstWhere(
      (v) => v.isDefault,
      orElse: () => full.variants.first,
    );
    final extraSourceVariants = full.variants
        .where((v) => v.id != defaultVariant.id)
        .toList();

    final tierEntries = await Future.wait(
      full.variants.map(
        (v) async => MapEntry(v.id, await _repo.wholesaleTiers(v.id)),
      ),
    );
    final tiersBySourceVariant = {for (final e in tierEntries) e.key: e.value};
    final toppingGroups = await _repo.toppingGroups(p.id);

    final extraVariants = <ProductVariant>[];
    final tiersByExtraVariant = <String, List<WholesaleTier>>{};
    for (final v in extraSourceVariants) {
      final tempId =
          'local-copy-${DateTime.now().microsecondsSinceEpoch}-${extraVariants.length}';
      extraVariants.add(
        ProductVariant(
          id: tempId,
          productId: '',
          sku: v.sku,
          name: v.name,
          price: v.price,
          comparePrice: v.comparePrice,
          costPrice: v.costPrice,
          wholesalePrice: v.wholesalePrice,
          isDefault: false,
          isActive: true,
        ),
      );
      tiersByExtraVariant[tempId] = tiersBySourceVariant[v.id] ?? [];
    }

    ref.read(copiedProductProvider.notifier).state = CopiedProduct(
      name: full.name,
      description: full.description,
      variantGroupName: full.variantGroupName,
      salesModel: full.salesModel,
      status: full.status,
      imageUrl: full.images.isNotEmpty ? full.images.first : null,
      defaultVariantName: defaultVariant.name,
      price: defaultVariant.price,
      defaultVariantTiers: tiersBySourceVariant[defaultVariant.id] ?? [],
      extraVariants: extraVariants,
      tiersByExtraVariant: tiersByExtraVariant,
      toppingGroupIds: toppingGroups.map((g) => g.id).toList(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã sao chép "${full.name}" — vào "Thêm sản phẩm" để dán lại.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

/// Sửa giá nhanh ngay từ danh sách, không cần mở màn "Sửa sản phẩm" đầy đủ — 1 biến thể thì
/// sửa thẳng, nhiều biến thể thì liệt kê từng biến thể để chọn đúng cái cần đổi giá.
Future<void> _quickEditPrice(
  BuildContext context,
  WidgetRef ref,
  Product p,
) async {
  if (p.variants.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sản phẩm chưa có biến thể/giá để sửa')),
    );
    return;
  }
  final controllers = {
    for (final v in p.variants)
      v.id: TextEditingController(text: v.price.toString()),
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
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final changed = p.variants.where((v) {
    final newPrice = int.tryParse(controllers[v.id]!.text.trim());
    return newPrice != null && newPrice != v.price;
  }).toList();
  if (changed.isEmpty) return;

  try {
    await Future.wait(
      changed.map(
        (v) => _repo.updateVariant(v.id, {
          'price': int.parse(controllers[v.id]!.text.trim()),
        }),
      ),
    );
    ref.invalidate(_productsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã cập nhật giá')));
    }
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

/// Kéo thả đổi thứ tự hiển thị cho khách ở màn chi tiết cửa hàng — chỉ ghi lại sort_order cho
/// những sản phẩm THẬT SỰ đổi vị trí (giống cách categories_screen.dart bên app admin làm),
/// tự "chữa" luôn trường hợp nhiều sản phẩm cũ đang cùng sort_order=0 (chưa từng sắp xếp) chỉ
/// sau 1 lần kéo.
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
        await _repo.update(reordered[i].id, {'sort_order': i});
      }
    }
    ref.invalidate(_productsProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}

/// Kéo thả đổi thứ tự nhóm topping hiển thị cho khách ở màn chi tiết sản phẩm — cùng pattern
/// với [_reorder] ở trên.
Future<void> _reorderToppingGroups(
  BuildContext context,
  WidgetRef ref,
  List<ToppingGroup> groups,
  int oldIndex,
  int newIndex,
) async {
  final reordered = List<ToppingGroup>.from(groups);
  final item = reordered.removeAt(oldIndex);
  reordered.insert(newIndex, item);

  try {
    for (var i = 0; i < reordered.length; i++) {
      if (reordered[i].sortOrder != i) {
        await _repo.updateToppingGroup(reordered[i].id, {'sort_order': i});
      }
    }
    ref.invalidate(_toppingGroupsProvider);
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

  Widget _productCard(
    BuildContext context,
    WidgetRef ref,
    Product p,
    int index,
  ) {
    final isActive = p.status == 'active';
    return Card(
      key: ValueKey(p.id),
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
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${p.variants.length} biến thể · từ ${formatVnd(p.lowestPrice)}',
                                  style: Theme.of(context).textTheme.bodySmall,
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
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: isActive,
                      onChanged: (_) => _toggleActive(context, ref, p),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Sao chép sản phẩm',
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _copyProduct(context, ref, p),
                      ),
                      IconButton(
                        tooltip: 'Xoá sản phẩm',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _confirmDelete(context, ref, p),
                      ),
                      // Kéo để đổi thứ tự hiển thị cho khách — xem [_reorder].
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
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
    int index,
  ) {
    return Card(
      key: ValueKey('group-${g.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/topping-groups/${g.id}/edit'),
        title: Text(g.name),
        subtitle: Text(
          g.linkedProductCount > 0
              ? 'Đã liên kết với ${g.linkedProductCount} món'
              : 'Chưa liên kết sản phẩm nào',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Xoá nhóm topping',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDeleteToppingGroup(context, ref, g),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(_productsProvider);
    final toppingGroupsAsync = ref.watch(_toppingGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Sản phẩm'),
        actions: const [NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_productsProvider);
          ref.invalidate(_toppingGroupsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 2 nút hành động chính — 4/5 bề ngang màn hình, chữ tự thu nhỏ (FittedBox) nếu
            // vẫn không đủ chỗ thay vì tràn/xuống dòng lệch.
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.8,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/topping-groups/new'),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.add, size: 18),
                              SizedBox(width: 4),
                              Text('Thêm topping'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.push('/products/new'),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.add, size: 18),
                              SizedBox(width: 4),
                              Text('Thêm sản phẩm'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
            if ((productsAsync.valueOrNull?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              StatCard(
                label: 'Tổng sản phẩm',
                value: '${productsAsync.valueOrNull!.length}',
                icon: Icons.inventory_2_outlined,
              ),
            ],
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
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: groups.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorderToppingGroups(
                            context,
                            ref,
                            groups,
                            oldIndex,
                            newIndex,
                          ),
                      itemBuilder: (context, index) =>
                          _toppingGroupCard(context, ref, groups[index], index),
                    ),
            ),
            if ((toppingGroupsAsync.valueOrNull?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              StatCard(
                label: 'Tổng nhóm topping',
                value: '${toppingGroupsAsync.valueOrNull!.length}',
                icon: Icons.local_offer_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
