import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/category_icons.dart';
import '../../core/cloudinary_uploader.dart';
import '../../models/category.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/icon_picker_dialog.dart';
import '../../widgets/icon_picker_field.dart';

/// Danh mục ngành hàng dùng chung cho cả sàn — tối đa 2 cấp (gốc và con), mỗi cấp đều
/// chọn được icon. Chỉ admin được tạo/sửa — cửa hàng chỉ gắn sản phẩm vào danh mục có sẵn.
/// Cố ý KHÔNG cho xoá (kể cả admin): xoá 1 danh mục gốc/con sẽ kéo theo mất luôn mọi
/// merchant_categories mà từng cửa hàng tự tạo dựa trên nó (ON DELETE CASCADE) — rủi ro mất
/// dữ liệu 2 tầng khó lường trước, xem server/src/routes/products.js.
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

  /// Chỉ danh mục con được, không cho chọn tiếp danh mục con làm cha (giới hạn 2 cấp).
  Future<void> _addDialog(List<Category> all, {String? parentId}) async {
    final roots = all.where((c) => c.parentId == null).toList();
    final nameCtrl = TextEditingController();
    String? selectedParent = parentId;
    String? iconName;
    String? iconUrl;
    var iconVersion = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Thêm danh mục'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
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
                      ...roots.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (v) => setInner(() => selectedParent = v),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Icon danh mục (hiện ở trang chủ app khách) — chọn 1 trong 2 nguồn:',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      IconPickerField(
                        key: ValueKey('material-$iconVersion'),
                        label: 'Icon Material có sẵn',
                        initialIconName: iconName,
                        onChanged: (name) => setInner(() {
                          iconName = name;
                          iconUrl = null;
                          iconVersion++;
                        }),
                      ),
                      _LibraryIconPickerField(
                        key: ValueKey('library-$iconVersion'),
                        initialIconUrl: iconUrl,
                        onChanged: (url) => setInner(() {
                          iconUrl = url;
                          iconName = null;
                          iconVersion++;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
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
      // Danh mục mới luôn xếp ở cuối nhóm anh em của nó (cha giống nhau), không giành chỗ
      // của danh mục đã sắp xếp trước đó.
      final siblings = all.where((c) => c.parentId == selectedParent);
      final nextSortOrder =
          siblings.isEmpty ? 0 : siblings.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
      await ref.read(adminRepoProvider).createCategory(
            name: name,
            // slug phải là duy nhất toàn sàn, thêm hậu tố thời gian để không đụng tên trùng
            slug: '${_slugify(name)}-${DateTime.now().millisecondsSinceEpoch % 10000}',
            parentId: selectedParent,
            iconName: iconName,
            iconUrl: iconUrl,
            sortOrder: nextSortOrder,
          );
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDialog(Category category) async {
    final nameCtrl = TextEditingController(text: category.name);
    String? iconName = category.iconName;
    String? iconUrl = category.iconUrl;
    var iconVersion = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa danh mục'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Tên danh mục', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Icon danh mục — chọn 1 trong 2 nguồn:',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      IconPickerField(
                        key: ValueKey('material-$iconVersion'),
                        label: 'Icon Material có sẵn',
                        initialIconName: iconName,
                        onChanged: (name) => setInner(() {
                          iconName = name;
                          iconUrl = null;
                          iconVersion++;
                        }),
                      ),
                      _LibraryIconPickerField(
                        key: ValueKey('library-$iconVersion'),
                        initialIconUrl: iconUrl,
                        onChanged: (url) => setInner(() {
                          iconUrl = url;
                          iconName = null;
                          iconVersion++;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateCategory(category.id, {
        'name': nameCtrl.text.trim(),
        'icon_name': iconName,
        'icon_url': iconUrl,
      });
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Đổi vị trí [category] lên/xuống 1 bậc trong nhóm anh em [siblings] (đã sắp theo thứ tự
  /// hiện tại). Ghi lại sort_order tuần tự 0..n-1 cho cả nhóm — tự "chữa" luôn trường hợp
  /// nhiều danh mục cũ đang cùng sort_order=0 (chưa từng sắp xếp) chỉ sau 1 lần bấm.
  Future<void> _move(List<Category> siblings, int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= siblings.length) return;

    final reordered = List<Category>.from(siblings);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);

    setState(() => _busy = true);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          await ref.read(adminRepoProvider).updateCategory(reordered[i].id, {'sort_order': i});
        }
      }
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
          final roots = all.where((c) => c.parentId == null).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          if (all.isEmpty) return const Center(child: Text('Chưa có danh mục nào'));

          List<Category> childrenOf(String id) => all.where((c) => c.parentId == id).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              ...roots.asMap().entries.map((entry) {
                final rootIndex = entry.key;
                final root = entry.value;
                final kids = childrenOf(root.id);
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: kids.isEmpty
                      ? ListTile(
                          leading: _CategoryLeadingIcon(iconUrl: root.iconUrl, iconName: root.iconName),
                          title: Text(root.name),
                          subtitle: Text(root.slug, style: theme.textTheme.bodySmall),
                          trailing: _CategoryActions(
                            busy: _busy,
                            onMoveUp: rootIndex > 0 ? () => _move(roots, rootIndex, -1) : null,
                            onMoveDown: rootIndex < roots.length - 1 ? () => _move(roots, rootIndex, 1) : null,
                            onAddChild: () => _addDialog(all, parentId: root.id),
                            onEdit: () => _editDialog(root),
                          ),
                        )
                      : ExpansionTile(
                          leading: _CategoryLeadingIcon(iconUrl: root.iconUrl, iconName: root.iconName),
                          title: Text(root.name),
                          subtitle: Text('${kids.length} danh mục con', style: theme.textTheme.bodySmall),
                          trailing: _CategoryActions(
                            busy: _busy,
                            onMoveUp: rootIndex > 0 ? () => _move(roots, rootIndex, -1) : null,
                            onMoveDown: rootIndex < roots.length - 1 ? () => _move(roots, rootIndex, 1) : null,
                            onAddChild: () => _addDialog(all, parentId: root.id),
                            onEdit: () => _editDialog(root),
                          ),
                          children: [
                            ...kids.asMap().entries.map((kidEntry) {
                              final kidIndex = kidEntry.key;
                              final kid = kidEntry.value;
                              return Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: ListTile(
                                    dense: true,
                                    leading: _CategoryLeadingIcon(iconUrl: kid.iconUrl, iconName: kid.iconName, size: 22),
                                    title: Text(kid.name),
                                    trailing: _CategoryActions(
                                      busy: _busy,
                                      onMoveUp: kidIndex > 0 ? () => _move(kids, kidIndex, -1) : null,
                                      onMoveDown: kidIndex < kids.length - 1 ? () => _move(kids, kidIndex, 1) : null,
                                      onEdit: () => _editDialog(kid),
                                    ),
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

class _CategoryActions extends StatelessWidget {
  final bool busy;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onAddChild;
  final VoidCallback onEdit;

  const _CategoryActions({
    required this.busy,
    this.onMoveUp,
    this.onMoveDown,
    this.onAddChild,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Đưa lên trên',
          icon: const Icon(Icons.arrow_upward),
          onPressed: busy || onMoveUp == null ? null : onMoveUp,
        ),
        IconButton(
          tooltip: 'Đưa xuống dưới',
          icon: const Icon(Icons.arrow_downward),
          onPressed: busy || onMoveDown == null ? null : onMoveDown,
        ),
        if (onAddChild != null)
          IconButton(
            tooltip: 'Thêm danh mục con',
            icon: const Icon(Icons.add),
            onPressed: busy ? null : onAddChild,
          ),
        IconButton(
          tooltip: 'Sửa',
          icon: const Icon(Icons.edit_outlined),
          onPressed: busy ? null : onEdit,
        ),
      ],
    );
  }
}

class _CategoryLeadingIcon extends StatelessWidget {
  final String? iconUrl;
  final String? iconName;
  final double size;
  const _CategoryLeadingIcon({this.iconUrl, this.iconName, this.size = 24});

  @override
  Widget build(BuildContext context) {
    if (iconName != null && iconName!.isNotEmpty) {
      return Icon(categoryIconOf(iconName), size: size, color: Theme.of(context).colorScheme.primary);
    }
    if (iconUrl == null || iconUrl!.isEmpty) return Icon(Icons.folder_outlined, size: size);
    return Image.network(
      iconUrl!,
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.primary,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (_, _, _) => Icon(Icons.folder_outlined, size: size),
    );
  }
}

/// Chọn 1 icon từ thư viện Lucide/Online (mở popup dùng chung với màn Icon tabbar), tải lên
/// Cloudinary rồi trả về URL — cùng kiểu ô vuông 140x140 với IconPickerField (icon Material)
/// để 2 lựa chọn nhìn cân đối cạnh nhau trong dialog thêm/sửa danh mục.
class _LibraryIconPickerField extends StatefulWidget {
  final String? initialIconUrl;
  final ValueChanged<String?> onChanged;
  const _LibraryIconPickerField({super.key, this.initialIconUrl, required this.onChanged});

  @override
  State<_LibraryIconPickerField> createState() => _LibraryIconPickerFieldState();
}

class _LibraryIconPickerFieldState extends State<_LibraryIconPickerField> {
  String? _iconUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _iconUrl = widget.initialIconUrl;
  }

  Future<void> _pick() async {
    final picked = await showIconPickerDialog(context);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final secureUrl = await CloudinaryUploader().uploadImage(
        picked.bytes,
        picked.filename,
        folder: 'categories',
      );
      final pngUrl = toCloudinaryPngUrl(secureUrl);
      if (mounted) setState(() => _iconUrl = pngUrl);
      widget.onChanged(pngUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Icon từ thư viện (Lucide/Online)', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: _uploading ? null : _pick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : _iconUrl != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Image.network(
                          _iconUrl!,
                          fit: BoxFit.contain,
                          color: theme.colorScheme.primary,
                          colorBlendMode: BlendMode.srcIn,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline, color: theme.colorScheme.outline, size: 28),
                            const SizedBox(height: 4),
                            Text('Chọn icon', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}
