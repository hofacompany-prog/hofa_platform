import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/category_grid.dart';

/// Toàn bộ danh mục ở 1 cấp — [parentId] null thì hiện danh mục gốc (mở từ ô "Xem tất
/// cả" trên trang chủ), có giá trị thì hiện danh mục con của [parentId] (mở từ ô "Xem
/// tất cả" trên màn chi tiết danh mục cha). Bấm vào 1 ô: danh mục gốc thì mở màn chi
/// tiết (có danh mục con + sản phẩm nổi bật), danh mục con thì mở thẳng danh sách sản phẩm.
class AllCategoriesScreen extends ConsumerWidget {
  final String? parentId;
  final String? parentName;

  const AllCategoriesScreen({super.key, this.parentId, this.parentName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isRoot = parentId == null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(isRoot ? 'Tất cả danh mục' : (parentName ?? 'Danh mục con')),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (categories) {
          final items = categories.where((c) => c.parentId == parentId).toList();
          if (items.isEmpty) return const Center(child: Text('Chưa có danh mục nào'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 4,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (context, i) {
              final c = items[i];
              return CategoryTile(
                label: c.name,
                iconUrl: c.iconUrl,
                iconName: c.iconName,
                onTap: () => isRoot
                    ? context.push('/categories/${c.id}', extra: c.name)
                    : context.push('/categories/${c.id}/products', extra: c.name),
              );
            },
          );
        },
      ),
    );
  }
}
