import 'package:flutter/material.dart';
import '../core/category_icons.dart';

/// Chọn 1 icon từ toàn bộ icon Material Design có sẵn (xem core/category_icons.dart) —
/// dùng cho icon danh mục thay vì bắt tải ảnh lên. Hơn 2000 icon nên bắt buộc có ô tìm
/// kiếm để lọc theo tên (tiếng Anh, vd "food", "car", "book").
class IconPickerField extends StatefulWidget {
  final String label;
  final String? initialIconName;
  final ValueChanged<String> onChanged;

  const IconPickerField({
    super.key,
    required this.label,
    this.initialIconName,
    required this.onChanged,
  });

  @override
  State<IconPickerField> createState() => _IconPickerFieldState();
}

class _IconPickerFieldState extends State<IconPickerField> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialIconName;
  }

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _IconPickerSheet(selected: _selected),
    );
    if (picked == null) return;
    setState(() => _selected = picked);
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: _selected != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(categoryIconOf(_selected), size: 36, color: theme.colorScheme.primary),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          categoryIconLabel(_selected!),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
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

class _IconPickerSheet extends StatefulWidget {
  final String? selected;
  const _IconPickerSheet({this.selected});

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  final _searchCtrl = TextEditingController();
  late List<String> _keys;

  @override
  void initState() {
    super.initState();
    _keys = categoryIcons.keys.toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _keys = q.isEmpty ? categoryIcons.keys.toList() : categoryIcons.keys.where((k) => k.contains(q.replaceAll(' ', '_'))).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chọn icon danh mục (${categoryIcons.length} icon)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Tìm icon theo tên tiếng Anh, vd: food, car, book...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: _keys.isEmpty
                  ? const Center(child: Text('Không tìm thấy icon nào'))
                  : GridView.builder(
                      itemCount: _keys.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.85,
                      ),
                      itemBuilder: (context, i) {
                        final key = _keys[i];
                        final isSelected = key == widget.selected;
                        return InkWell(
                          onTap: () => Navigator.pop(context, key),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                              border: isSelected ? Border.all(color: theme.colorScheme.primary) : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(categoryIcons[key], color: theme.colorScheme.primary),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Text(
                                    categoryIconLabel(key),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
