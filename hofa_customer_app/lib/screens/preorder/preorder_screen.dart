import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/cart_item.dart';
import '../../models/delivery_slot.dart';
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

String _weekdayLabelOf(int iso) =>
    _weekdayLabels.firstWhere((d) => d.iso == iso).label;

/// Giỏ "đặt trước" — cùng dùng chung cartProvider với giỏ hàng thường (giỏ chỉ chứa
/// món của 1 cửa hàng tại 1 thời điểm), chỉ hiển thị khi giỏ đang ở sales_model
/// 'scheduled' (bán sỉ/đặt trước). Chia dọc 2 cột: trái là danh sách sản phẩm — bấm vào
/// dòng "Ngày giao" nhỏ dưới tên mở popup chọn ngày (lịch) như bình thường, mỗi sản
/// phẩm chọn được nhiều ngày. Phải là cột ngày — bấm vào 1 ngày CHỈ để xem những sản
/// phẩm nào phải giao ngày đó. Giờ giao KHÔNG chọn theo từng món nữa — chỉ có đúng 1
/// giờ giao chung cho cả đơn, chọn ở phần "Hình thức giao" bên dưới.
class PreorderScreen extends ConsumerStatefulWidget {
  const PreorderScreen({super.key});

  @override
  ConsumerState<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends ConsumerState<PreorderScreen> {
  int? _selectedViewDay;
  int _weekOffset = 0;
  String _mode = 'once';
  int _weeks = 1;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);

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

  /// Ngày gần nhất (từ ngày mai) khớp thứ [iso] — dùng để hiển thị ngày dương lịch cho
  /// 1 slot, không lưu ngày cụ thể (slot lặp theo thứ trong tuần).
  DateTime _nearestFutureDate(int iso) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    var d = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    while (d.weekday != iso) {
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

  /// Popup chọn ngày giao (lịch) như bình thường cho 1 sản phẩm — không chọn giờ ở đây,
  /// giờ giao chung cho cả đơn chọn riêng ở phần "Hình thức giao". Thêm được nhiều ngày,
  /// mỗi ngày chỉ giữ lại thứ trong tuần (slot lặp hàng tuần) nên không thêm trùng thứ.
  Future<void> _editScheduleDialog(CartItem item) async {
    var slots = [...item.deliverySlots];

    Future<void> addSlot(StateSetter setInner) async {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 90)),
      );
      if (date == null) return;
      if (slots.any((s) => s.weekday == date.weekday)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_weekdayLabelOf(date.weekday)} đã được chọn rồi',
              ),
            ),
          );
        }
        return;
      }
      slots = [...slots, DeliverySlot(weekday: date.weekday, time: _time)]
        ..sort(DeliverySlot.compare);
      await ref
          .read(cartProvider.notifier)
          .updateDeliverySlots(item.lineId, slots);
      setInner(() {});
    }

    void removeSlot(DeliverySlot slot, StateSetter setInner) {
      slots = slots.where((s) => s.weekday != slot.weekday).toList();
      ref.read(cartProvider.notifier).updateDeliverySlots(item.lineId, slots);
      setInner(() {});
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) {
          final sorted = [...slots]..sort(DeliverySlot.compare);
          return AlertDialog(
            title: Text('Ngày giao cho "${item.productName}"'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sorted.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Chưa có ngày giao nào'),
                    ),
                  ...sorted.map(
                    (s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_weekdayLabelOf(s.weekday)} (${_shortDate(_nearestFutureDate(s.weekday))})',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => removeSlot(s, setInner),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm ngày giao'),
                    onPressed: () => addSlot(setInner),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Xong'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _goCheckout(CartState cart) {
    for (final item in cart.items) {
      if (item.deliverySlots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chọn ít nhất 1 ngày giao cho "${item.productName}"'),
          ),
        );
        return;
      }
    }
    final allWeekdays = <int>{};
    for (final item in cart.items) {
      for (final s in item.deliverySlots) {
        allWeekdays.add(s.weekday);
      }
    }
    final schedule = PreorderSchedule(
      slots: (allWeekdays.toList()..sort())
          .map((w) => DeliverySlot(weekday: w, time: _time))
          .toList(),
      recurring: _mode == 'recurring',
      weeks: _mode == 'recurring' ? _weeks : 1,
    );
    context.push('/checkout', extra: schedule);
  }

  Widget _itemCard(BuildContext context, CartItem item) {
    final theme = Theme.of(context);
    final toppingGroups =
        ref.watch(toppingGroupsProvider(item.productId)).valueOrNull ?? [];
    final hasToppings = toppingGroups.isNotEmpty;
    final sortedSlots = [...item.deliverySlots]..sort(DeliverySlot.compare);

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
                NetworkImageBox(url: item.productImage, width: 44, height: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(item.variantName, style: theme.textTheme.bodySmall),
                      if (item.toppings.isNotEmpty)
                        Text(
                          item.toppings.map((t) => t.name).join(', '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      Text(
                        formatVnd(item.unitPrice + item.toppingsTotal),
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () =>
                      ref.read(cartProvider.notifier).removeItem(item.lineId),
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
                    item.toppings.isEmpty ? 'Chọn topping' : 'Sửa topping',
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
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(item.lineId, item.quantity - 1),
                ),
                Text('${item.quantity}'),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(item.lineId, item.quantity + 1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _editScheduleDialog(item),
              child: Text(
                sortedSlots.isEmpty
                    ? 'Chưa chọn ngày giao — bấm để chọn'
                    : 'Ngày giao: ${sortedSlots.map((s) => '${_weekdayLabelOf(s.weekday)} (${_shortDate(_nearestFutureDate(s.weekday))})').join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: sortedSlots.isEmpty
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: sortedSlots.isEmpty
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayPicker(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    final viewDay = _selectedViewDay;
    final itemsForViewDay = viewDay == null
        ? <CartItem>[]
        : cart.items
              .where((i) => i.deliverySlots.any((s) => s.weekday == viewDay))
              .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ngày giao trong tuần', style: theme.textTheme.titleSmall),
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
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _weekOffset++),
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
            final hasAny = cart.items.any(
              (i) => i.deliverySlots.any((s) => s.weekday == d.iso),
            );
            return FilterChip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_shortDate(date), style: const TextStyle(fontSize: 10)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (hasAny) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              selected: viewDay == d.iso,
              onSelected: !selectable
                  ? null
                  : (_) => setState(() => _selectedViewDay = d.iso),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (viewDay == null)
          Text(
            'Bấm vào 1 ngày để xem những món phải giao hôm đó',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else ...[
          Text(
            'Ngày ${_weekdayLabelOf(viewDay)} (${_shortDate(_nearestFutureDate(viewDay))}) cần giao:',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (itemsForViewDay.isEmpty)
            Text(
              'Chưa có món nào giao ngày này',
              style: theme.textTheme.bodySmall,
            )
          else
            ...itemsForViewDay.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${i.productName}'),
              ),
            ),
        ],
      ],
    );
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
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
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                          children: cart.items
                              .map((item) => _itemCard(context, item))
                              .toList(),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _dayPicker(context, cart)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Giờ giao', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_outlined),
                        label: Text('Giờ giao: ${_time.format(context)}'),
                        onPressed: _pickTime,
                      ),
                      const SizedBox(height: 16),
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
