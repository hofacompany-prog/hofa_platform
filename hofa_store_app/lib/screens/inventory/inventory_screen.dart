import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/branch.dart';
import '../../models/inventory_item.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/inventory_repository.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/product_repository.dart';

class _InventoryData {
  final Branch branch;
  final List<InventoryItem> items;
  final Map<String, String> variantLabels; // variant_id -> "Sản phẩm - biến thể"
  _InventoryData({required this.branch, required this.items, required this.variantLabels});
}

final _inventoryProvider = FutureProvider.autoDispose<_InventoryData?>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return null;

  final branches = await MerchantRepository().branches(merchant.id);
  if (branches.isEmpty) return null;
  final branch = branches.firstWhere((b) => b.isMain, orElse: () => branches.first);

  final products = await ProductRepository().list(merchant.id);
  final labels = <String, String>{};
  for (final p in products) {
    for (final v in p.variants) {
      labels[v.id] = '${p.name} — ${v.name}';
    }
  }

  final items = await InventoryRepository().list(branch.id);
  return _InventoryData(branch: branch, items: items, variantLabels: labels);
});

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _adjustDialog(BuildContext context, WidgetRef ref, _InventoryData data) async {
    final variantOptions = data.variantLabels.entries.toList();
    if (variantOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có sản phẩm nào để nhập kho')));
      return;
    }
    String selectedVariantId = variantOptions.first.key;
    String moveType = 'purchase_in';
    final qtyCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Điều chỉnh tồn kho'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedVariantId,
                decoration: const InputDecoration(labelText: 'Sản phẩm'),
                items: variantOptions
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => selectedVariantId = v ?? selectedVariantId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: moveType,
                decoration: const InputDecoration(labelText: 'Loại'),
                items: const [
                  DropdownMenuItem(value: 'purchase_in', child: Text('Nhập kho')),
                  DropdownMenuItem(value: 'adjustment', child: Text('Điều chỉnh kiểm kê')),
                  DropdownMenuItem(value: 'damage_out', child: Text('Hư hỏng / huỷ')),
                  DropdownMenuItem(value: 'return_in', child: Text('Khách trả lại')),
                ],
                onChanged: (v) => setState(() => moveType = v ?? moveType),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                decoration: InputDecoration(
                  labelText: 'Số lượng',
                  helperText: moveType == 'damage_out' ? 'Nhập số dương, hệ thống tự trừ kho' : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(signed: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    var qty = int.tryParse(qtyCtrl.text.trim());
    if (qty == null || qty == 0) return;
    if (moveType == 'damage_out' && qty > 0) qty = -qty;

    try {
      await InventoryRepository().adjust(
        branchId: data.branch.id,
        variantId: selectedVariantId,
        moveType: moveType,
        quantity: qty,
      );
      ref.invalidate(_inventoryProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_inventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kho hàng'),
        actions: [
          dataAsync.maybeWhen(
            data: (d) => d == null
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          if (data == null) return const Center(child: Text('Chưa có chi nhánh nào'));
          if (data.items.isEmpty) {
            return const Center(child: Text('Chưa có tồn kho — thêm sản phẩm rồi nhập kho'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = data.items[i];
              final label = data.variantLabels[item.variantId] ?? item.variantId;
              final low = item.quantityOnHand <= item.lowStockThreshold;
              return Card(
                child: ListTile(
                  title: Text(label),
                  subtitle: Text('Đang có: ${item.quantityOnHand} · Đã giữ: ${item.quantityReserved}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${item.quantityAvailable}', style: Theme.of(context).textTheme.titleMedium),
                      Text('còn bán được', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  leading: low ? const Icon(Icons.warning_amber, color: Colors.orange) : const Icon(Icons.inventory_2_outlined),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
