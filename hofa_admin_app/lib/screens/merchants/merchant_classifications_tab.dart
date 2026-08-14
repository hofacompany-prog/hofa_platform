import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/responsive.dart';
import '../../models/merchant_classification.dart';
import '../../providers/admin_providers.dart';

/// Tab quản lý danh sách phân loại cửa hàng (Nhà hàng/Cà phê/Siêu thị mini...) — cửa hàng chọn
/// nhiều phân loại cùng lúc lúc tạo/sửa, khách lọc theo phân loại ở trang chủ app Khách hàng.
/// Mirror hoàn toàn _BanksTab (payment_settings_screen.dart) — cùng pattern CRUD đơn giản.
class MerchantClassificationsTab extends ConsumerWidget {
  const MerchantClassificationsTab({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    MerchantClassification? item,
  }) async {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Thêm phân loại' : 'Sửa phân loại'),
        content: SizedBox(
          width: dialogWidth(context, 360),
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên phân loại',
              helperText: 'Vd: Nhà hàng, Cà phê, Siêu thị mini...',
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
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      if (item == null) {
        await ref
            .read(adminRepoProvider)
            .createMerchantClassification(name: nameCtrl.text.trim());
      } else {
        await ref.read(adminRepoProvider).updateMerchantClassification(
          item.id,
          {'name': nameCtrl.text.trim()},
        );
      }
      ref.invalidate(merchantClassificationsProvider);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MerchantClassification item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá phân loại?'),
        content: Text(
          'Xoá "${item.name}" khỏi danh sách — cửa hàng đã gắn phân loại này sẽ tự mất gắn kết.',
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
    try {
      await ref.read(adminRepoProvider).deleteMerchantClassification(item.id);
      ref.invalidate(merchantClassificationsProvider);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(merchantClassificationsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh sách phân loại cửa hàng',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Cửa hàng chọn nhiều phân loại cùng lúc lúc tạo/sửa hồ sơ. Khách lọc cửa hàng '
                  'theo phân loại này ở trang chủ app Khách hàng.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                itemsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (items) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Chưa có phân loại nào — bấm nút + để thêm.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }
                    return Column(
                      children: items
                          .map(
                            (c) => Card(
                              elevation: 0,
                              color: theme.colorScheme.surfaceContainerLow,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  c.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _edit(context, ref, item: c),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(context, ref, c),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
