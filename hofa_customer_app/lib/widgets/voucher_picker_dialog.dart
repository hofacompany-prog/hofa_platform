import 'package:flutter/material.dart';
import '../core/format.dart';
import '../models/voucher.dart';

/// Popup chọn voucher (trượt lên từ dưới, cùng kiểu với topping_picker_dialog.dart) — cho
/// khách bấm chọn 1 trong các voucher công khai của cửa hàng (không cần gõ mã) hoặc tự
/// nhập mã riêng ở cuối. Chỉ trả về MÃ đã chọn/gõ (String) — checkout_screen.dart tự gọi
/// lại API kiểm tra mã như cũ, popup này không tự áp dụng.
Future<String?> showVoucherPickerDialog(
  BuildContext context, {
  required List<Voucher> vouchers,
  required int orderAmount,
  List<String> excludeCodes = const [],
}) {
  final customCodeCtrl = TextEditingController();
  final excludeUpper = excludeCodes.map((c) => c.toUpperCase()).toSet();
  final selectable = vouchers
      .where((v) => !excludeUpper.contains(v.code.toUpperCase()))
      .toList();

  return showModalBottomSheet<String>(
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
                  'Chọn voucher',
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
                    if (selectable.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          vouchers.isEmpty
                              ? 'Cửa hàng chưa có voucher công khai nào.'
                              : 'Đã áp dụng hết voucher công khai của cửa hàng.',
                        ),
                      )
                    else
                      ...selectable.map(
                        (v) =>
                            _VoucherTile(voucher: v, orderAmount: orderAmount),
                      ),
                    const Divider(height: 32),
                    Text(
                      'Hoặc nhập mã khác',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customCodeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'Nhập mã voucher',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (v) {
                              final code = v.trim();
                              if (code.isNotEmpty) Navigator.pop(context, code);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            final code = customCodeCtrl.text.trim();
                            if (code.isNotEmpty) Navigator.pop(context, code);
                          },
                          child: const Text('Dùng'),
                        ),
                      ],
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
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VoucherTile extends StatelessWidget {
  final Voucher voucher;
  final int orderAmount;
  const _VoucherTile({required this.voucher, required this.orderAmount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible =
        !voucher.isExpired && orderAmount >= voucher.minOrderAmount;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: eligible ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voucher.code,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      voucher.discountLabel(formatVnd),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (voucher.description != null &&
                        voucher.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        voucher.description!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      !eligible && voucher.isExpired
                          ? 'Đã hết hạn'
                          : !eligible
                          ? 'Cần mua thêm ${formatVnd(voucher.minOrderAmount - orderAmount)} để dùng mã này'
                          : voucher.minOrderAmount > 0
                          ? 'Đơn tối thiểu ${formatVnd(voucher.minOrderAmount)}'
                          : 'Áp dụng cho mọi đơn hàng',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: !eligible
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: eligible
                  ? () => Navigator.pop(context, voucher.code)
                  : null,
              child: const Text('Dùng'),
            ),
          ],
        ),
      ),
    );
  }
}
