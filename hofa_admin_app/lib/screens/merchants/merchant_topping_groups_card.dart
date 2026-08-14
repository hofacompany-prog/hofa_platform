import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../models/merchant.dart';
import '../../models/topping.dart';
import '../../providers/admin_providers.dart';

/// Quản lý nhóm topping + lựa chọn topping của 1 cửa hàng — cùng dữ liệu cửa hàng tự quản lý
/// ở hofa_store_app/lib/screens/toppings/topping_group_form_screen.dart, admin xem/sửa được
/// nhờ requireMerchantAccess() cho role admin luôn qua (xem server/src/utils.js). Sắp xếp
/// bằng nút lên/xuống (giống categories_screen.dart) thay vì kéo thả, vì đang lồng trong
/// 1 Card cuộn chung với cả màn chi tiết cửa hàng.
class MerchantToppingGroupsCard extends ConsumerStatefulWidget {
  final Merchant merchant;
  const MerchantToppingGroupsCard({super.key, required this.merchant});

  @override
  ConsumerState<MerchantToppingGroupsCard> createState() =>
      _MerchantToppingGroupsCardState();
}

class _MerchantToppingGroupsCardState
    extends ConsumerState<MerchantToppingGroupsCard> {
  bool _busy = false;

  String get _merchantId => widget.merchant.id;

  void _invalidate() =>
      ref.invalidate(merchantToppingGroupsProvider(_merchantId));

  Future<void> _groupDialog({ToppingGroup? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var isRequired = existing?.isRequired ?? false;
    var allowMultiple = existing?.allowMultiple ?? false;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(
            existing == null ? 'Thêm nhóm topping' : 'Sửa nhóm topping',
          ),
          content: SizedBox(
            width: dialogWidth(context, 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm (VD: Chọn topping, Độ ngọt)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bắt buộc chọn'),
                    value: isRequired,
                    onChanged: (v) => setInner(() => isRequired = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho chọn nhiều mục'),
                    value: allowMultiple,
                    onChanged: (v) => setInner(() => allowMultiple = v),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setInner(() => error = 'Nhập tên nhóm');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final data = {
      'name': nameCtrl.text.trim(),
      'is_required': isRequired,
      'allow_multiple': allowMultiple,
    };
    try {
      if (existing == null) {
        await ref.read(adminRepoProvider).createToppingGroup(_merchantId, data);
      } else {
        await ref.read(adminRepoProvider).updateToppingGroup(existing.id, data);
      }
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteGroup(ToppingGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá nhóm topping?'),
        content: Text(
          'Xoá "${g.name}" cùng toàn bộ lựa chọn bên trong? Sản phẩm đang gắn nhóm này sẽ '
          'mất luôn nhóm topping đó.',
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
      await ref.read(adminRepoProvider).deleteToppingGroup(g.id);
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _moveGroup(
    List<ToppingGroup> groups,
    int index,
    int direction,
  ) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= groups.length) return;
    final reordered = List<ToppingGroup>.from(groups);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);

    setState(() => _busy = true);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          await ref.read(adminRepoProvider).updateToppingGroup(
            reordered[i].id,
            {'sort_order': i},
          );
        }
      }
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toppingDialog(ToppingGroup group, {Topping? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing?.price.toString() ?? '0',
    );
    var isActive = existing?.isActive ?? true;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(existing == null ? 'Thêm lựa chọn' : 'Sửa lựa chọn'),
          content: SizedBox(
            width: dialogWidth(context, 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên (VD: Trân châu đen)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá cộng thêm (VNĐ, để 0 nếu miễn phí)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Đang hiện với khách'),
                    subtitle: const Text(
                      'Tắt = tạm ẩn (VD: hết hàng), không xoá',
                    ),
                    value: isActive,
                    onChanged: (v) => setInner(() => isActive = v),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setInner(() => error = 'Nhập tên lựa chọn');
                  return;
                }
                if (int.tryParse(priceCtrl.text.trim()) == null) {
                  setInner(() => error = 'Nhập giá hợp lệ');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final data = {
      'name': nameCtrl.text.trim(),
      'price': int.parse(priceCtrl.text.trim()),
      'is_active': isActive,
    };
    try {
      if (existing == null) {
        await ref.read(adminRepoProvider).createTopping(group.id, data);
      } else {
        await ref.read(adminRepoProvider).updateTopping(existing.id, data);
      }
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _toggleToppingActive(Topping t) async {
    try {
      await ref.read(adminRepoProvider).updateTopping(t.id, {
        'is_active': !t.isActive,
      });
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteTopping(Topping t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá lựa chọn?'),
        content: Text('Xoá "${t.name}" khỏi nhóm topping này?'),
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
      await ref.read(adminRepoProvider).deleteTopping(t.id);
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _moveTopping(
    ToppingGroup group,
    List<Topping> toppings,
    int index,
    int direction,
  ) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= toppings.length) return;
    final reordered = List<Topping>.from(toppings);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);

    setState(() => _busy = true);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          await ref.read(adminRepoProvider).updateTopping(reordered[i].id, {
            'sort_order': i,
          });
        }
      }
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(merchantToppingGroupsProvider(_merchantId));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_offer_outlined,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nhóm topping',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _groupDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm nhóm'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tạo 1 lần rồi gắn vào nhiều sản phẩm — sắp xếp và bật/tắt từng lựa chọn ở đây '
              'áp dụng ngay cho màn sản phẩm của khách.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            groupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Lỗi tải nhóm topping: $e'),
              data: (groups) {
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Chưa có nhóm topping nào.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var gi = 0; gi < groups.length; gi++)
                      _groupTile(context, theme, groups, gi),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(
    BuildContext context,
    ThemeData theme,
    List<ToppingGroup> groups,
    int gi,
  ) {
    final g = groups[gi];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        title: Text(
          g.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Wrap(
          spacing: 6,
          children: [
            if (g.isRequired)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('Bắt buộc'),
              ),
            if (g.allowMultiple)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('Chọn nhiều'),
              ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${g.toppings.length} lựa chọn'),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Lên',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: _busy || gi == 0
                  ? null
                  : () => _moveGroup(groups, gi, -1),
            ),
            IconButton(
              tooltip: 'Xuống',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: _busy || gi == groups.length - 1
                  ? null
                  : () => _moveGroup(groups, gi, 1),
            ),
            IconButton(
              tooltip: 'Sửa nhóm',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _groupDialog(existing: g),
            ),
            IconButton(
              tooltip: 'Xoá nhóm',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteGroup(g),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (g.toppings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Chưa có lựa chọn nào trong nhóm này.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  for (var ti = 0; ti < g.toppings.length; ti++)
                    _toppingRow(context, theme, g, ti),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _toppingDialog(g),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Thêm lựa chọn'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toppingRow(
    BuildContext context,
    ThemeData theme,
    ToppingGroup g,
    int ti,
  ) {
    final t = g.toppings[ti];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Opacity(
        opacity: t.isActive ? 1 : 0.5,
        child: Row(
          children: [
            Expanded(
              child: Text(
                t.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              t.price > 0 ? '+${formatVnd(t.price)}' : 'Miễn phí',
              style: theme.textTheme.bodySmall,
            ),
            Switch(
              value: t.isActive,
              onChanged: (_) => _toggleToppingActive(t),
            ),
            IconButton(
              tooltip: 'Lên',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: _busy || ti == 0
                  ? null
                  : () => _moveTopping(g, g.toppings, ti, -1),
            ),
            IconButton(
              tooltip: 'Xuống',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: _busy || ti == g.toppings.length - 1
                  ? null
                  : () => _moveTopping(g, g.toppings, ti, 1),
            ),
            IconButton(
              tooltip: 'Sửa',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: () => _toppingDialog(g, existing: t),
            ),
            IconButton(
              tooltip: 'Xoá',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _deleteTopping(t),
            ),
          ],
        ),
      ),
    );
  }
}
