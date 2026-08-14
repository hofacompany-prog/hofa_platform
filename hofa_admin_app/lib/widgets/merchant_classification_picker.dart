import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_providers.dart';

/// Chọn nhiều phân loại cửa hàng (Nhà hàng/Cà phê/Siêu thị mini...) qua viên nang — dùng chung ở
/// màn tạo cửa hàng và chỉnh sửa cửa hàng (admin app).
class MerchantClassificationPicker extends ConsumerWidget {
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const MerchantClassificationPicker({
    super.key,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(merchantClassificationsProvider);

    return itemsAsync.when(
      loading: () => const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text('Lỗi tải phân loại: $e'),
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'Chưa có phân loại nào — vào tab "Phân loại cửa hàng" để thêm.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((c) {
            final selected = selectedIds.contains(c.id);
            return FilterChip(
              label: Text(c.name),
              selected: selected,
              onSelected: (v) {
                final next = Set<String>.from(selectedIds);
                v ? next.add(c.id) : next.remove(c.id);
                onChanged(next);
              },
            );
          }).toList(),
        );
      },
    );
  }
}
