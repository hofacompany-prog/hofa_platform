import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/category.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';
import '../../widgets/nav_back_button.dart';
import '../../widgets/stat_card.dart';

class _CategoriesData {
  final String merchantId;
  final List<Category> allCategories;
  final List<MerchantCategory> merchantCategories;
  _CategoriesData({
    required this.merchantId,
    required this.allCategories,
    required this.merchantCategories,
  });
}

final _categoriesDataProvider = FutureProvider.autoDispose<_CategoriesData?>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return null;
  final repo = ProductRepository();
  final all = await repo.categories();
  final mine = await repo.merchantCategories(merchantId: merchant.id);
  return _CategoriesData(
    merchantId: merchant.id,
    allCategories: all,
    merchantCategories: mine,
  );
});

/// Quản lý "danh mục cửa hàng" — mỗi danh mục nằm dưới 1 danh mục con hệ thống, dùng để
/// nhóm sản phẩm khi khách xem cửa hàng (xem thêm ghi chú ở product_form_screen.dart).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  List<Category> _roots(List<Category> all) =>
      all.where((c) => c.parentId == null).toList();

  List<Category> _childrenOf(List<Category> all, String parentId) =>
      all.where((c) => c.parentId == parentId).toList();

  Future<void> _categoryDialog(
    BuildContext context,
    WidgetRef ref,
    _CategoriesData data, {
    MerchantCategory? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String? parentId;
    String? childId = existing?.categoryId;
    if (childId != null) {
      final child = data.allCategories.where((c) => c.id == childId);
      parentId = child.isNotEmpty ? child.first.parentId : null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) {
          final roots = _roots(data.allCategories);
          final children = parentId != null
              ? _childrenOf(data.allCategories, parentId!)
              : const <Category>[];
          return AlertDialog(
            title: Text(
              existing == null
                  ? 'Thêm danh mục cửa hàng'
                  : 'Sửa danh mục cửa hàng',
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: parentId,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục chính',
                        border: OutlineInputBorder(),
                      ),
                      items: roots
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setInner(() {
                        parentId = v;
                        childId = null;
                      }),
                    ),
                    if (parentId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: childId,
                        decoration: const InputDecoration(
                          labelText: 'Danh mục con',
                          border: OutlineInputBorder(),
                        ),
                        items: children
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setInner(() => childId = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Tên danh mục cửa hàng',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || childId == null || nameCtrl.text.trim().isEmpty) return;

    final repo = ProductRepository();
    try {
      if (existing == null) {
        await repo.createMerchantCategory(
          merchantId: data.merchantId,
          categoryId: childId!,
          name: nameCtrl.text.trim(),
        );
      } else {
        await repo.updateMerchantCategory(existing.id, {
          'category_id': childId,
          'name': nameCtrl.text.trim(),
        });
      }
      ref.invalidate(_categoriesDataProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteDialog(
    BuildContext context,
    WidgetRef ref,
    MerchantCategory mc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá danh mục?'),
        content: Text(
          'Xoá danh mục "${mc.name}"? Sản phẩm đang gắn danh mục này sẽ chỉ mất tag, không bị xoá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProductRepository().deleteMerchantCategory(mc.id);
      ref.invalidate(_categoriesDataProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_categoriesDataProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Danh mục'),
        actions: [
          dataAsync.maybeWhen(
            data: (d) => d == null
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: FilledButton.icon(
                      onPressed: () => _categoryDialog(context, ref, d),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm danh mục'),
                    ),
                  ),
            orElse: () => const SizedBox(),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Chưa có cửa hàng'));
          }
          if (data.merchantCategories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text('Cửa hàng chưa có danh mục nào'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _categoryDialog(context, ref, data),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm danh mục đầu tiên'),
                  ),
                ],
              ),
            );
          }

          // Nhóm theo "Danh mục chính › Danh mục con" để dễ theo dõi.
          final byId = {for (final c in data.allCategories) c.id: c};
          String groupLabel(String categoryId) {
            final child = byId[categoryId];
            if (child == null) return 'Khác';
            final parent = child.parentId != null ? byId[child.parentId] : null;
            return parent != null
                ? '${parent.name} › ${child.name}'
                : child.name;
          }

          final grouped = <String, List<MerchantCategory>>{};
          for (final mc in data.merchantCategories) {
            (grouped[groupLabel(mc.categoryId)] ??= []).add(mc);
          }
          final groupKeys = grouped.keys.toList()..sort();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final key in groupKeys) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 8),
                  child: Text(
                    key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ...grouped[key]!.map(
                  (mc) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(mc.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _categoryDialog(
                              context,
                              ref,
                              data,
                              existing: mc,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteDialog(context, ref, mc),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              StatCard(
                label: 'Tổng danh mục',
                value: '${data.merchantCategories.length}',
                icon: Icons.category_outlined,
              ),
            ],
          );
        },
      ),
    );
  }
}
