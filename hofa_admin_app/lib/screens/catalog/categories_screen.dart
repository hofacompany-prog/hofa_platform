import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/category.dart';
import '../../providers/admin_providers.dart';

/// Danh mục ngành hàng dùng chung cho cả sàn (Thực phẩm > Rau củ quả > Rau ăn lá).
/// Chỉ admin được tạo/sửa — cửa hàng chỉ gắn sản phẩm vào danh mục có sẵn.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _busy = false;

  String _slugify(String name) {
    var s = name.toLowerCase().trim();
    const from = 'áàảãạăắằẳẵặâấầẩẫậđéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵ';
    const to = 'aaaaaaaaaaaaaaaaadeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyy';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '').replaceAll(RegExp(r'\s+'), '-');
  }

  Future<void> _addDialog(List<Category> existing, {String? parentId}) async {
    final nameCtrl = TextEditingController();
    String? selectedParent = parentId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Thêm danh mục'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên danh mục',
                    hintText: 'VD: Rau ăn lá',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: selectedParent,
                  decoration: const InputDecoration(labelText: 'Thuộc danh mục cha', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Danh mục gốc —')),
                    ...existing.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setInner(() => selectedParent = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thêm')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final name = nameCtrl.text.trim();
      await ref.read(adminRepoProvider).createCategory(
            name: name,
            // slug phải là duy nhất toàn sàn, thêm hậu tố thời gian để không đụng tên trùng
            slug: '${_slugify(name)}-${DateTime.now().millisecondsSinceEpoch % 10000}',
            parentId: selectedParent,
          );
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh mục ngành hàng'),
        actions: [
          categoriesAsync.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _addDialog(list),
                icon: const Icon(Icons.add),
                label: const Text('Thêm danh mục'),
              ),
            ),
            orElse: () => const SizedBox(),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (all) {
          final roots = all.where((c) => c.parentId == null).toList();
          if (all.isEmpty) return const Center(child: Text('Chưa có danh mục nào'));

          // Dựng cây 2 cấp trở lên: hiện danh mục gốc, lồng các con bên dưới
          List<Category> childrenOf(String id) => all.where((c) => c.parentId == id).toList();

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              ...roots.map((root) {
                final kids = childrenOf(root.id);
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: kids.isEmpty
                      ? ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(root.name),
                          subtitle: Text(root.slug, style: theme.textTheme.bodySmall),
                          trailing: IconButton(
                            tooltip: 'Thêm danh mục con',
                            icon: const Icon(Icons.add),
                            onPressed: _busy ? null : () => _addDialog(all, parentId: root.id),
                          ),
                        )
                      : ExpansionTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(root.name),
                          subtitle: Text('${kids.length} danh mục con', style: theme.textTheme.bodySmall),
                          children: [
                            ...kids.map((kid) {
                              final grandKids = childrenOf(kid.id);
                              return Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Column(
                                  children: [
                                    ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
                                      title: Text(kid.name),
                                      trailing: IconButton(
                                        tooltip: 'Thêm danh mục con',
                                        icon: const Icon(Icons.add, size: 18),
                                        onPressed: _busy ? null : () => _addDialog(all, parentId: kid.id),
                                      ),
                                    ),
                                    ...grandKids.map((g) => Padding(
                                          padding: const EdgeInsets.only(left: 32),
                                          child: ListTile(
                                            dense: true,
                                            leading: const Icon(Icons.circle, size: 6),
                                            title: Text(g.name),
                                          ),
                                        )),
                                  ],
                                ),
                              );
                            }),
                            Padding(
                              padding: const EdgeInsets.only(left: 24, bottom: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _busy ? null : () => _addDialog(all, parentId: root.id),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Thêm vào nhóm này'),
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
