import 'package:flutter/material.dart';
import '../core/format.dart';
import '../models/topping.dart';

/// Dialog chọn topping dùng chung cho lúc thêm vào giỏ (product_detail_screen) và lúc
/// sửa topping của 1 dòng đã có trong giỏ (cart_screen/preorder_screen). Trả về danh
/// sách topping đã chọn, hoặc null nếu khách bấm Huỷ.
Future<List<ProductTopping>?> showToppingPickerDialog(
  BuildContext context, {
  required List<ToppingGroup> groups,
  List<ProductTopping> initiallySelected = const [],
}) {
  final selectedByGroup = <String, Set<String>>{
    for (final g in groups)
      g.id: initiallySelected
          .where((t) => g.toppings.any((gt) => gt.id == t.id))
          .map((t) => t.id)
          .toSet(),
  };

  return showDialog<List<ProductTopping>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setInner) => AlertDialog(
        title: const Text('Chọn topping'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final g in groups) ...[
                  Row(
                    children: [
                      Text(
                        g.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (g.isRequired)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '(bắt buộc)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (g.allowMultiple)
                    ...g.toppings.map(
                      (t) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectedByGroup[g.id]!.contains(t.id),
                        title: Text(
                          t.price > 0
                              ? '${t.name} (+${formatVnd(t.price)})'
                              : t.name,
                        ),
                        onChanged: (v) => setInner(() {
                          if (v == true) {
                            selectedByGroup[g.id]!.add(t.id);
                          } else {
                            selectedByGroup[g.id]!.remove(t.id);
                          }
                        }),
                      ),
                    )
                  else
                    RadioGroup<String>(
                      groupValue: selectedByGroup[g.id]!.isEmpty
                          ? null
                          : selectedByGroup[g.id]!.first,
                      onChanged: (v) => setInner(
                        () => selectedByGroup[g.id] = v == null ? {} : {v},
                      ),
                      child: Column(
                        children: g.toppings
                            .map(
                              (t) => RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: t.id,
                                title: Text(
                                  t.price > 0
                                      ? '${t.name} (+${formatVnd(t.price)})'
                                      : t.name,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              for (final g in groups) {
                if (g.isRequired && (selectedByGroup[g.id] ?? {}).isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Vui lòng chọn ${g.name}')),
                  );
                  return;
                }
              }
              final result = <ProductTopping>[];
              for (final g in groups) {
                final ids = selectedByGroup[g.id] ?? {};
                result.addAll(g.toppings.where((t) => ids.contains(t.id)));
              }
              Navigator.pop(context, result);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ),
  );
}
