import 'package:flutter/material.dart';
import '../core/category_icons.dart';

/// Chọn 1 icon từ bộ icon dựng sẵn (xem core/category_icons.dart) — dùng cho icon danh
/// mục thay vì bắt tải ảnh lên, đủ dùng cho phần lớn danh mục ngành hàng phổ biến.
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
                      Text(categoryIconLabels[_selected] ?? _selected!, style: theme.textTheme.bodySmall),
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

class _IconPickerSheet extends StatelessWidget {
  final String? selected;
  const _IconPickerSheet({this.selected});

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
            Text('Chọn icon danh mục', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 360,
              child: GridView.builder(
                itemCount: categoryIcons.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemBuilder: (context, i) {
                  final key = categoryIcons.keys.elementAt(i);
                  final isSelected = key == selected;
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
                          Text(
                            categoryIconLabels[key] ?? key,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
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
