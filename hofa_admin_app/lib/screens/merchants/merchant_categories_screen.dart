import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/responsive.dart';
import '../../models/category.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';

/// Quản lý danh mục RIÊNG của 1 cửa hàng (merchant_categories) — khác hẳn danh mục ngành hàng
/// hệ thống (catalog/categories_screen.dart, admin quản lý chung cho cả sàn, cửa hàng chỉ chọn
/// từ đó). Mỗi mục ở đây nằm dưới ĐÚNG 1 danh mục con hệ thống đã chọn, tên hiển thị do cửa
/// hàng (hoặc admin thay mặt) tự đặt — khách xem trang chi tiết cửa hàng CHỈ thấy danh mục ở
/// màn này, không thấy cây hệ thống. Sản phẩm gắn vào các mục này qua
/// products.merchant_category_id — xoá 1 mục chỉ khiến sản phẩm đang gắn mất gắn kết (NULL),
/// không xoá sản phẩm (xem server/src/routes/products.js).
class MerchantCategoriesScreen extends ConsumerStatefulWidget {
  final Merchant merchant;
  const MerchantCategoriesScreen({super.key, required this.merchant});

  @override
  ConsumerState<MerchantCategoriesScreen> createState() =>
      _MerchantCategoriesScreenState();
}

class _MerchantCategoriesScreenState
    extends ConsumerState<MerchantCategoriesScreen> {
  bool _busy = false;

  Category? _findCategory(List<Category> all, String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _addDialog(
    List<Category> systemCategories,
    List<MerchantCategory> current,
  ) async {
    final roots = systemCategories.where((c) => c.parentId == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    String? selectedParentId;
    String? selectedChildId;
    final nameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) {
          final children = selectedParentId == null
              ? <Category>[]
              : (systemCategories
                      .where((c) => c.parentId == selectedParentId)
                      .toList()
                    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
          return AlertDialog(
            title: const Text('Thêm danh mục cửa hàng'),
            content: SizedBox(
              width: dialogWidth(context, 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String?>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục cha (hệ thống)',
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
                        selectedParentId = v;
                        selectedChildId = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedChildId,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục con (hệ thống)',
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
                      onChanged: selectedParentId == null
                          ? null
                          : (v) => setInner(() {
                              selectedChildId = v;
                              // Gợi ý sẵn tên hiển thị = tên danh mục con hệ thống — sửa lại
                              // được ngay, chỉ để đỡ phải gõ tay trong trường hợp thường gặp.
                              if (nameCtrl.text.trim().isEmpty && v != null) {
                                final child = children.firstWhere(
                                  (c) => c.id == v,
                                );
                                nameCtrl.text = child.name;
                              }
                            }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị cho khách',
                        hintText: 'VD: Đồ uống, Món chính...',
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
                onPressed: selectedChildId == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Thêm'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || selectedChildId == null || nameCtrl.text.trim().isEmpty)
      return;

    setState(() => _busy = true);
    try {
      // Mục mới luôn xếp CUỐI CÙNG trong toàn bộ danh sách danh mục của cửa hàng — server sắp
      // xếp merchant_categories theo 1 dãy sort_order DUY NHẤT cho cả cửa hàng (không tách
      // riêng theo danh mục con hệ thống, xem GET /merchant-categories ORDER BY sort_order),
      // nên phải tính theo TOÀN BỘ [current], không lọc theo selectedChildId.
      final nextSortOrder = current.isEmpty
          ? 0
          : current.map((m) => m.sortOrder).reduce((a, b) => a > b ? a : b) +
                1;
      await ref
          .read(adminRepoProvider)
          .createMerchantCategory(
            merchantId: widget.merchant.id,
            categoryId: selectedChildId!,
            name: nameCtrl.text.trim(),
            sortOrder: nextSortOrder,
          );
      ref.invalidate(merchantCategoriesProvider(widget.merchant.id));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDialog(MerchantCategory item) async {
    final nameCtrl = TextEditingController(text: item.name);
    var isActive = item.isActive;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa danh mục cửa hàng'),
          content: SizedBox(
            width: dialogWidth(context, 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang hoạt động'),
                  subtitle: const Text('Tắt sẽ ẩn danh mục này khỏi trang cửa hàng'),
                  value: isActive,
                  onChanged: (v) => setInner(() => isActive = v),
                ),
              ],
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
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateMerchantCategory(item.id, {
        'name': nameCtrl.text.trim(),
        'is_active': isActive,
      });
      ref.invalidate(merchantCategoriesProvider(widget.merchant.id));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(MerchantCategory item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá danh mục cửa hàng?'),
        content: Text(
          'Xoá "${item.name}" khỏi cửa hàng — sản phẩm đang gắn danh mục này sẽ mất gắn kết '
          '(sản phẩm không bị xoá).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).deleteMerchantCategory(item.id);
      ref.invalidate(merchantCategoriesProvider(widget.merchant.id));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Đổi vị trí [siblings][index] lên/xuống 1 bậc — [siblings] PHẢI là TOÀN BỘ danh mục của
  /// cửa hàng (đã sắp theo sort_order), KHÔNG lọc theo danh mục con hệ thống: server sắp xếp
  /// merchant_categories theo 1 dãy sort_order duy nhất cho cả cửa hàng (xem
  /// GET /merchant-categories ORDER BY sort_order — khác cây 2 cấp cha/con của danh mục hệ
  /// thống ở catalog/categories_screen.dart, nơi hàm _move gốc này được mirror từ đó). Lọc
  /// theo categoryId ở đây từng khiến mỗi nhóm chỉ còn 1 mục — nút lên/xuống bị khoá vĩnh
  /// viễn vì không có "anh em" nào để đổi chỗ.
  Future<void> _move(
    List<MerchantCategory> siblings,
    int index,
    int direction,
  ) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= siblings.length) return;

    final reordered = List<MerchantCategory>.from(siblings);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);

    setState(() => _busy = true);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          await ref
              .read(adminRepoProvider)
              .updateMerchantCategory(reordered[i].id, {'sort_order': i});
        }
      }
      ref.invalidate(merchantCategoriesProvider(widget.merchant.id));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systemCategoriesAsync = ref.watch(categoriesProvider);
    final itemsAsync = ref.watch(merchantCategoriesProvider(widget.merchant.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Danh mục — ${widget.merchant.name}'),
        actions: [
          if (systemCategoriesAsync.hasValue && itemsAsync.hasValue)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                          _addDialog(systemCategoriesAsync.value!, itemsAsync.value!),
                icon: const Icon(Icons.add),
                label: const Text('Thêm danh mục'),
              ),
            ),
        ],
      ),
      body: systemCategoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (systemCategories) => itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text('Cửa hàng chưa có danh mục nào — bấm "Thêm danh mục".'),
              );
            }

            // 1 DÃY DUY NHẤT cho cả cửa hàng — KHÔNG nhóm/tách theo danh mục con hệ thống, vì
            // trang cửa hàng thật (app Khách) hiện toàn bộ danh mục của cửa hàng theo đúng 1
            // sort_order chung (xem GET /merchant-categories ORDER BY sort_order). Danh mục
            // con hệ thống mỗi mục đang gắn vào chỉ hiện làm phụ đề tham khảo, không dùng để
            // nhóm hay giới hạn phạm vi lên/xuống.
            final ordered = List<MerchantCategory>.from(items)
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                ...ordered.asMap().entries.map((entry) {
                  final index = entry.key;
                  final m = entry.value;
                  final child = _findCategory(systemCategories, m.categoryId);
                  final parent = _findCategory(systemCategories, child?.parentId);
                  final path = [
                    if (parent != null) parent.name,
                    if (child != null) child.name,
                  ].join(' › ');

                  return Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        m.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [if (path.isNotEmpty) path, if (!m.isActive) 'Đã tắt']
                            .join(' · '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Đưa lên trên',
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: _busy || index == 0
                                  ? null
                                  : () => _move(ordered, index, -1),
                            ),
                            IconButton(
                              tooltip: 'Đưa xuống dưới',
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: _busy || index == ordered.length - 1
                                  ? null
                                  : () => _move(ordered, index, 1),
                            ),
                            IconButton(
                              tooltip: 'Sửa',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: _busy ? null : () => _editDialog(m),
                            ),
                            IconButton(
                              tooltip: 'Xoá',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy ? null : () => _delete(m),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
