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
/// 'scheduled' (bán sỉ/đặt trước). Bộ chọn ngày trong tuần dùng CHUNG 1 chỗ — bấm vào
/// món nào thì bộ chọn nhảy theo, hiển thị/sửa đúng ngày của món đó. Ngày tính từ
/// ngày mai trở đi (không cho chọn hôm nay), có nút xem tuần kế tiếp.
class PreorderScreen extends ConsumerStatefulWidget {
  const PreorderScreen({super.key});

  @override
  ConsumerState<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends ConsumerState<PreorderScreen> {
  String? _activeLineId;
  int _weekOffset = 0;
  String _mode = 'once';
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  int _weeks = 1;

  /// Thứ 2 của tuần chứa "ngày mai" — mốc gốc để tính ngày cho mọi tuần xem tiếp theo.
  DateTime get _baseMonday {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final d = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  DateTime _dateFor(int isoWeekday, int weekOffset) =>
      _baseMonday.add(Duration(days: 7 * weekOffset + (isoWeekday - 1)));

  bool _isSelectable(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    return !date.isBefore(tomorrowDate);
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

    CartItem? activeItem;
    if (isPreorderCart) {
      final matches = cart.items.where((i) => i.lineId == _activeLineId);
      activeItem = matches.isNotEmpty ? matches.first : cart.items.first;
      _activeLineId = activeItem.lineId;
    }

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
                        final isActive = item.lineId == activeItem?.lineId;
                        return InkWell(
                          onTap: () =>
                              setState(() => _activeLineId = item.lineId),
                          child: Card(
                            elevation: 0,
                            color: isActive
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.08,
                                  )
                                : theme.colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isActive
                                  ? BorderSide(color: theme.colorScheme.primary)
                                  : BorderSide.none,
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                color:
                                                    theme.colorScheme.primary,
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
                                  const SizedBox(height: 4),
                                  Text(
                                    item.weekdays.isEmpty
                                        ? 'Chưa chọn ngày giao'
                                        : 'Ngày giao: ${item.weekdays.map((iso) => _weekdayLabels.firstWhere((d) => d.iso == iso).label).join(', ')}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: item.weekdays.isEmpty
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 32),
                      Text(
                        'Ngày giao trong tuần cho "${activeItem?.productName ?? ''}"',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: _weekOffset > 0
                                ? () => setState(() => _weekOffset--)
                                : null,
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                '${_shortDate(_dateFor(1, _weekOffset))} - ${_shortDate(_dateFor(7, _weekOffset))}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _weekOffset++),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Tuần sau'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _weekdayLabels.map((d) {
                          final date = _dateFor(d.iso, _weekOffset);
                          final selectable = _isSelectable(date);
                          return FilterChip(
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _shortDate(date),
                                  style: const TextStyle(fontSize: 10),
                                ),
                                Text(
                                  d.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            selected:
                                activeItem?.weekdays.contains(d.iso) ?? false,
                            onSelected: (!selectable || activeItem == null)
                                ? null
                                : (_) => _toggleDay(activeItem!, d.iso),
                          );
                        }).toList(),
                      ),
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
