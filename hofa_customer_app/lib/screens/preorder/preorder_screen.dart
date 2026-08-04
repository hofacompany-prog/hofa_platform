import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/cart_item.dart';
import '../../models/preorder_schedule.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/topping_picker_dialog.dart';

const _weekdayLabels = [
  (iso: 1, label: 'T2'),
  (iso: 2, label: 'T3'),
  (iso: 3, label: 'T4'),
  (iso: 4, label: 'T5'),
  (iso: 5, label: 'T6'),
  (iso: 6, label: 'T7'),
  (iso: 7, label: 'CN'),
];

/// Giỏ "đặt trước" — cùng dùng chung cartProvider với giỏ hàng thường (giỏ chỉ chứa
/// món của 1 cửa hàng tại 1 thời điểm), chỉ hiển thị khi giỏ đang ở sales_model
/// 'scheduled' (bán sỉ/đặt trước). Mỗi món tự chọn ngày giao riêng trong tuần (dùng để
/// tính đủ điều kiện bậc giá của chính món đó) — hình thức giao (1 lần/nhiều lần) +
/// giờ giao là chung cho cả đơn vì vẫn chỉ giao 1 chuyến/lần.
class PreorderScreen extends ConsumerStatefulWidget {
  const PreorderScreen({super.key});

  @override
  ConsumerState<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends ConsumerState<PreorderScreen> {
  String _mode = 'once';
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  int _weeks = 1;

  /// Ngày dương lịch gần nhất khớp thứ [isoWeekday] (1=T2..7=CN), tính từ hôm nay —
  /// chỉ để hiển thị trên chip chọn thứ, không phụ thuộc giờ giao đã chọn.
  DateTime _nextDateFor(int isoWeekday) {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    while (d.weekday != isoWeekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _toggleDay(CartItem item, int iso) {
    final days = Set<int>.from(item.weekdays);
    if (days.contains(iso)) {
      days.remove(iso);
    } else {
      days.add(iso);
    }
    ref
        .read(cartProvider.notifier)
        .updateWeekdays(item.lineId, days.toList()..sort());
  }

  Future<void> _editToppings(CartItem item) async {
    final groups = await ref
        .read(productRepoProvider)
        .toppingGroups(item.productId);
    if (groups.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sản phẩm này không có topping')),
        );
      }
      return;
    }
    if (!mounted) return;
    final result = await showToppingPickerDialog(
      context,
      groups: groups,
      initiallySelected: item.toppings,
    );
    if (result != null) {
      await ref.read(cartProvider.notifier).updateToppings(item.lineId, result);
    }
  }

  void _goCheckout(CartState cart) {
    for (final item in cart.items) {
      if (item.weekdays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chọn ít nhất 1 ngày giao cho "${item.productName}"'),
          ),
        );
        return;
      }
    }
    final allDays = <int>{};
    for (final item in cart.items) {
      allDays.addAll(item.weekdays);
    }
    final schedule = PreorderSchedule(
      weekdays: allDays.toList()..sort(),
      time: _time,
      recurring: _mode == 'recurring',
      weeks: _mode == 'recurring' ? _weeks : 1,
    );
    context.push('/checkout', extra: schedule);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final isPreorderCart = !cart.isEmpty && cart.salesModel == 'scheduled';

    return Scaffold(
      appBar: AppBar(title: const Text('Đặt trước')),
      body: !isPreorderCart
          ? const Center(
              child: Text('Chưa có sản phẩm đặt trước/bán sỉ nào trong giỏ'),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cart.merchantName ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...cart.items.map((item) {
                        final toppingGroups =
                            ref
                                .watch(toppingGroupsProvider(item.productId))
                                .valueOrNull ??
                            [];
                        final hasToppings = toppingGroups.isNotEmpty;
                        return Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    NetworkImageBox(
                                      url: item.productImage,
                                      width: 52,
                                      height: 52,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            item.variantName,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          if (item.toppings.isNotEmpty)
                                            Text(
                                              item.toppings
                                                  .map((t) => t.name)
                                                  .join(', '),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .secondary,
                                                  ),
                                            ),
                                          Text(
                                            formatVnd(
                                              item.unitPrice +
                                                  item.toppingsTotal,
                                            ),
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => ref
                                          .read(cartProvider.notifier)
                                          .removeItem(item.lineId),
                                    ),
                                  ],
                                ),
                                if (hasToppings)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _editToppings(item),
                                      icon: const Icon(Icons.tune, size: 16),
                                      label: Text(
                                        item.toppings.isEmpty
                                            ? 'Chọn topping'
                                            : 'Sửa topping',
                                      ),
                                    ),
                                  ),
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    const Text('Số lượng'),
                                    const Spacer(),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => ref
                                          .read(cartProvider.notifier)
                                          .updateQuantity(
                                            item.lineId,
                                            item.quantity - 1,
                                          ),
                                    ),
                                    Text('${item.quantity}'),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => ref
                                          .read(cartProvider.notifier)
                                          .updateQuantity(
                                            item.lineId,
                                            item.quantity + 1,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ngày giao trong tuần',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _weekdayLabels
                                      .map(
                                        (d) => FilterChip(
                                          label: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _shortDate(_nextDateFor(d.iso)),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                              Text(
                                                d.label,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          selected: item.weekdays.contains(
                                            d.iso,
                                          ),
                                          onSelected: (_) =>
                                              _toggleDay(item, d.iso),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 32),
                      Text('Hình thức giao', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Giao 1 lần'),
                            selected: _mode == 'once',
                            onSelected: (_) => setState(() => _mode = 'once'),
                          ),
                          ChoiceChip(
                            label: const Text('Giao nhiều lần'),
                            selected: _mode == 'recurring',
                            onSelected: (_) =>
                                setState(() => _mode = 'recurring'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_outlined),
                        label: Text('Giờ giao: ${_time.format(context)}'),
                        onPressed: _pickTime,
                      ),
                      if (_mode == 'recurring') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Số tuần lặp lại'),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _weeks > 1
                                  ? () => setState(() => _weeks--)
                                  : null,
                            ),
                            Text(
                              '$_weeks',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _weeks < 12
                                  ? () => setState(() => _weeks++)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(
                            alpha: 0.08,
                          ),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng số món'),
                            Text('${cart.itemCount}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Phí ship'),
                            const Text('Miễn phí'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tổng tiền',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              formatVnd(cart.subtotal),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _goCheckout(cart),
                            child: const Text('Đến thanh toán'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
