import 'package:flutter/material.dart';
import '../core/format.dart';
import '../models/topping.dart';

/// Popup chọn topping (trượt lên từ dưới) dùng chung cho lúc thêm vào giỏ
/// (product_detail_screen) và lúc sửa topping của 1 dòng đã có trong giỏ
/// (cart_screen/preorder_screen). Trả về topping đã chọn + lưu ý riêng cho sản phẩm này
/// (khác với lưu ý chung của cả đơn hàng nhập ở bước thanh toán), hoặc null nếu khách
/// bấm Huỷ/vuốt xuống đóng popup.
Future<({List<ProductTopping> toppings, String? note})?>
showToppingPickerDialog(
  BuildContext context, {
  required List<ToppingGroup> groups,
  List<ProductTopping> initiallySelected = const [],
  String? initialNote,
}) {
  final selectedByGroup = <String, Set<String>>{
    for (final g in groups)
      g.id: initiallySelected
          .where((t) => g.toppings.any((gt) => gt.id == t.id))
          .map((t) => t.id)
          .toSet(),
  };
  final noteCtrl = TextEditingController(text: initialNote ?? '');

  return showModalBottomSheet<({List<ProductTopping> toppings, String? note})>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setInner) {
        void save() {
          for (final g in groups) {
            if (g.isRequired && (selectedByGroup[g.id] ?? {}).isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Vui lòng chọn ${g.name}')),
              );
              return;
            }
          }
          final toppings = <ProductTopping>[];
          for (final g in groups) {
            final ids = selectedByGroup[g.id] ?? {};
            toppings.addAll(g.toppings.where((t) => ids.contains(t.id)));
          }
          final note = noteCtrl.text.trim();
          Navigator.pop(context, (
            toppings: toppings,
            note: note.isEmpty ? null : note,
          ));
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
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
                      'Chọn topping',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final g in groups) ...[
                          Row(
                            children: [
                              Text(
                                g.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (g.isRequired)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '(bắt buộc)',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
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
                                () => selectedByGroup[g.id] = v == null
                                    ? {}
                                    : {v},
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
                        const Divider(height: 24),
                        Text(
                          'Lưu ý riêng cho sản phẩm này',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Khác với lưu ý chung của cả đơn hàng (nhập ở bước thanh toán)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noteCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'VD: không lấy đá, ít cay...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Huỷ'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: save,
                            child: const Text('Xác nhận'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
