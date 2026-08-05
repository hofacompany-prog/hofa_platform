import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/inventory_item.dart';
import '../../models/stock_movement.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/inventory_repository.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/product_repository.dart';

class _InventoryData {
  final List<Branch> branches;
  final Branch branch;
  final List<InventoryItem> items;
  final Map<String, String>
  variantLabels; // variant_id -> "Sản phẩm - biến thể"
  _InventoryData({
    required this.branches,
    required this.branch,
    required this.items,
    required this.variantLabels,
  });
}

/// Chi nhánh đang xem — null nghĩa là chưa chọn tay, tự dùng chi nhánh chính.
final _selectedBranchIdProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);
final _searchProvider = StateProvider.autoDispose<String>((ref) => '');

final _inventoryProvider = FutureProvider.autoDispose<_InventoryData?>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return null;

  final branches = await MerchantRepository().branches(merchant.id);
  if (branches.isEmpty) return null;

  final selectedId = ref.watch(_selectedBranchIdProvider);
  final matched = selectedId == null
      ? const <Branch>[]
      : branches.where((b) => b.id == selectedId).toList();
  final branch = matched.isNotEmpty
      ? matched.first
      : branches.firstWhere((b) => b.isMain, orElse: () => branches.first);

  final products = await ProductRepository().list(merchant.id);
  final labels = <String, String>{};
  for (final p in products) {
    for (final v in p.variants) {
      labels[v.id] = '${p.name} — ${v.name}';
    }
  }

  final items = await InventoryRepository().list(branch.id);
  return _InventoryData(
    branches: branches,
    branch: branch,
    items: items,
    variantLabels: labels,
  );
});

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _adjustDialog(
    BuildContext context,
    WidgetRef ref,
    _InventoryData data, {
    String? fixedVariantId,
    String? fixedLabel,
  }) async {
    final variantOptions = data.variantLabels.entries.toList();
    if (fixedVariantId == null && variantOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có sản phẩm nào để nhập kho')),
      );
      return;
    }
    String selectedVariantId = fixedVariantId ?? variantOptions.first.key;
    String moveType = 'purchase_in';
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Điều chỉnh tồn kho'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fixedLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        fixedLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedVariantId,
                      decoration: const InputDecoration(
                        labelText: 'Sản phẩm',
                        border: OutlineInputBorder(),
                      ),
                      items: variantOptions
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                e.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(
                        () => selectedVariantId = v ?? selectedVariantId,
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: moveType,
                    decoration: const InputDecoration(
                      labelText: 'Loại',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'purchase_in',
                        child: Text('Nhập kho'),
                      ),
                      DropdownMenuItem(
                        value: 'adjustment',
                        child: Text('Điều chỉnh kiểm kê'),
                      ),
                      DropdownMenuItem(
                        value: 'damage_out',
                        child: Text('Hư hỏng / huỷ'),
                      ),
                      DropdownMenuItem(
                        value: 'return_in',
                        child: Text('Khách trả lại'),
                      ),
                      DropdownMenuItem(
                        value: 'transfer_in',
                        child: Text('Chuyển kho đến'),
                      ),
                      DropdownMenuItem(
                        value: 'transfer_out',
                        child: Text('Chuyển kho đi'),
                      ),
                    ],
                    onChanged: (v) => setState(() => moveType = v ?? moveType),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    autofocus: fixedVariantId != null,
                    decoration: InputDecoration(
                      labelText: 'Số lượng',
                      helperText:
                          (moveType == 'damage_out' ||
                              moveType == 'transfer_out')
                          ? 'Nhập số dương, hệ thống tự trừ kho'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú (không bắt buộc)',
                      border: OutlineInputBorder(),
                      isDense: true,
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
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    var qty = int.tryParse(qtyCtrl.text.trim());
    if (qty == null || qty == 0) return;
    if ((moveType == 'damage_out' || moveType == 'transfer_out') && qty > 0) {
      qty = -qty;
    }

    try {
      await InventoryRepository().adjust(
        branchId: data.branch.id,
        variantId: selectedVariantId,
        moveType: moveType,
        quantity: qty,
        note: noteCtrl.text.trim(),
      );
      ref.invalidate(_inventoryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _thresholdDialog(
    BuildContext context,
    WidgetRef ref,
    _InventoryData data,
    InventoryItem item,
    String label,
  ) async {
    final ctrl = TextEditingController(text: item.lowStockThreshold.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa ngưỡng cảnh báo'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cảnh báo khi số lượng còn dưới',
                  helperText:
                      'Sản phẩm sẽ hiện "Sắp hết hàng" khi đang có ≤ số này',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
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
    );
    if (ok != true) return;
    final value = int.tryParse(ctrl.text.trim());
    if (value == null || value < 0) return;

    try {
      await InventoryRepository().updateLowStockThreshold(
        branchId: data.branch.id,
        variantId: item.variantId,
        lowStockThreshold: value,
      );
      ref.invalidate(_inventoryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _historySheet(
    BuildContext context,
    _InventoryData data,
    InventoryItem item,
    String label,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Lịch sử tồn kho — $label',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<StockMovement>>(
                future: InventoryRepository().movements(
                  branchId: data.branch.id,
                  variantId: item.variantId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi: ${snapshot.error}'));
                  }
                  final moves = snapshot.data ?? [];
                  if (moves.isEmpty) {
                    return const Center(
                      child: Text('Chưa có lịch sử thay đổi nào'),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: moves.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (context, i) {
                      final m = moves[i];
                      final positive = m.quantity > 0;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            positive
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: positive ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stockMoveTypeLabels[m.moveType] ?? m.moveType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  formatDateTime(m.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (m.note != null && m.note!.isNotEmpty)
                                  Text(
                                    m.note!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${positive ? '+' : ''}${m.quantity}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: positive ? Colors.green : Colors.red,
                                ),
                              ),
                              Text(
                                'Tồn sau: ${m.balanceAfter}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDialog(
    BuildContext context,
    WidgetRef ref,
    _InventoryData data,
    InventoryItem item,
    String label,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá khỏi kho?'),
        content: Text(
          item.quantityOnHand > 0
              ? 'Xoá "$label" khỏi danh sách tồn kho? Số lượng đang có '
                    '(${item.quantityOnHand}) sẽ tự động điều chỉnh về 0 và ghi lại '
                    'trong lịch sử trước khi xoá.'
              : 'Xoá "$label" khỏi danh sách tồn kho?',
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
      await InventoryRepository().delete(
        branchId: data.branch.id,
        variantId: item.variantId,
      );
      ref.invalidate(_inventoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá "$label" khỏi kho')));
      }
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
    final dataAsync = ref.watch(_inventoryProvider);
    final search = ref.watch(_searchProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kho hàng'),
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
                      onPressed: () => _adjustDialog(context, ref, d),
                      icon: const Icon(Icons.add),
                      label: const Text('Điều chỉnh tồn kho'),
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
            return const Center(child: Text('Chưa có chi nhánh nào'));
          }

          final lowStockCount = data.items
              .where((i) => i.quantityOnHand <= i.lowStockThreshold)
              .length;

          final filtered = search.trim().isEmpty
              ? data.items
              : data.items.where((i) {
                  final label = (data.variantLabels[i.variantId] ?? '')
                      .toLowerCase();
                  return label.contains(search.trim().toLowerCase());
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.branches.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String>(
                          initialValue: data.branch.id,
                          decoration: const InputDecoration(
                            labelText: 'Chi nhánh',
                            prefixIcon: Icon(Icons.storefront_outlined),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: data.branches
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(b.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              ref
                                      .read(_selectedBranchIdProvider.notifier)
                                      .state =
                                  v,
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _StatBox(
                            icon: Icons.inventory_2_outlined,
                            label: 'Sản phẩm đang theo dõi',
                            value: '${data.items.length}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatBox(
                            icon: Icons.warning_amber_outlined,
                            label: 'Sắp hết hàng',
                            value: '$lowStockCount',
                            accent: lowStockCount > 0 ? Colors.orange : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Tìm theo tên sản phẩm...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          ref.read(_searchProvider.notifier).state = v,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: data.items.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có tồn kho — thêm sản phẩm rồi nhập kho',
                        ),
                      )
                    : filtered.isEmpty
                    ? const Center(
                        child: Text('Không tìm thấy sản phẩm phù hợp'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final label =
                              data.variantLabels[item.variantId] ??
                              item.variantId;
                          final low =
                              item.quantityOnHand <= item.lowStockThreshold;
                          return Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: low
                                        ? Colors.orange.withValues(alpha: 0.15)
                                        : theme.colorScheme.primary.withValues(
                                            alpha: 0.1,
                                          ),
                                    child: Icon(
                                      low
                                          ? Icons.warning_amber
                                          : Icons.inventory_2_outlined,
                                      color: low
                                          ? Colors.orange
                                          : theme.colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 2,
                                          children: [
                                            Text(
                                              label,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (low)
                                              const Chip(
                                                label: Text('Sắp hết hàng'),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                backgroundColor: Color(
                                                  0x22FB8519,
                                                ),
                                                side: BorderSide.none,
                                                labelStyle: TextStyle(
                                                  color: Color(0xFFFB8519),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Đang có: ${item.quantityOnHand} · '
                                          'Đã giữ: ${item.quantityReserved} · '
                                          'Ngưỡng cảnh báo: ${item.lowStockThreshold}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${item.quantityAvailable}',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      Text(
                                        'còn bán được',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'adjust') {
                                        _adjustDialog(
                                          context,
                                          ref,
                                          data,
                                          fixedVariantId: item.variantId,
                                          fixedLabel: label,
                                        );
                                      }
                                      if (v == 'threshold') {
                                        _thresholdDialog(
                                          context,
                                          ref,
                                          data,
                                          item,
                                          label,
                                        );
                                      }
                                      if (v == 'history') {
                                        _historySheet(
                                          context,
                                          data,
                                          item,
                                          label,
                                        );
                                      }
                                      if (v == 'delete') {
                                        _deleteDialog(
                                          context,
                                          ref,
                                          data,
                                          item,
                                          label,
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'adjust',
                                        child: Text('Điều chỉnh tồn kho'),
                                      ),
                                      PopupMenuItem(
                                        value: 'threshold',
                                        child: Text('Sửa ngưỡng cảnh báo'),
                                      ),
                                      PopupMenuItem(
                                        value: 'history',
                                        child: Text('Xem lịch sử'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Xoá khỏi kho'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
