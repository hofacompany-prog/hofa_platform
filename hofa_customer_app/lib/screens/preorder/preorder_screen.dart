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
/// dòng "Ngày giao" nhỏ dưới tên mở popup danh sách T2-CN, bấm ngày nào ngày đó sáng
/// lên (chọn). Phải là cột ngày — bấm vào 1 ngày CHỈ để xem những sản
/// phẩm nào phải giao ngày đó. Giờ giao chỉ có đúng 1 giờ chung cho cả đơn. Chọn "Giao
/// nhiều lần" phải xác nhận lại số tuần trước khi lịch bên phải áp dụng.
class PreorderScreen extends ConsumerStatefulWidget {
  const PreorderScreen({super.key});

  @override
  ConsumerState<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends ConsumerState<PreorderScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int? _selectedViewDay;
  int _weekOffset = 0;
  String _mode = 'once';
  int _weeks = 1;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _recurringConfirmed = false;

  // ---- Tab "Giá sỉ" — chỉ chọn 1 ngày giao + 1 giờ giao chung cho cả đơn,
  // không có khái niệm ngày trong tuần / lặp lại như tab "Đặt trước". ----
  DateTime? _wholesaleDate;
  TimeOfDay _wholesaleTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickWholesaleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _wholesaleDate = picked);
  }

  Future<void> _pickWholesaleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wholesaleTime,
    );
    if (picked != null) setState(() => _wholesaleTime = picked);
  }

  void _goCheckoutWholesale(CartState cart) {
    if (_wholesaleDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn ngày giao trước khi thanh toán')),
      );
      return;
    }
    final scheduledFor = DateTime(
      _wholesaleDate!.year,
      _wholesaleDate!.month,
      _wholesaleDate!.day,
      _wholesaleTime.hour,
      _wholesaleTime.minute,
    );
    context.push('/checkout', extra: scheduledFor);
  }

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

  /// Tuần [weekOffset] có nằm trong phạm vi lịch giao hiện tại không — "giao 1 lần" chỉ
  /// tính tuần gần nhất, "giao nhiều lần" đã xác nhận chỉ tính đúng số tuần đã chọn.
  /// Chưa xác nhận lặp lại thì chưa giới hạn, để khách tự do chọn ngày trước.
  bool _weekInRange(int weekOffset) {
    if (_mode == 'once') return weekOffset == 0;
    if (_mode == 'recurring' && _recurringConfirmed) {
      return weekOffset >= 0 && weekOffset < _weeks;
    }
    return true;
  }

  /// Tổng tiền của cả tuần đang xem — mỗi món tính theo số ngày trong tuần đó mà món
  /// này có lịch giao (1 món giao 2 ngày/tuần thì cộng 2 lần).
  int _weekTotal(CartState cart) {
    if (!_weekInRange(_weekOffset)) return 0;
    var total = 0;
    for (final item in cart.items) {
      final days = item.deliverySlots.map((s) => s.weekday).toSet().length;
      total += item.lineTotal * days;
    }
    return total;
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

  /// Popup chọn ngày giao cho 1 sản phẩm — danh sách T2 đến CN, bấm vào ngày nào thì
  /// ngày đó sáng lên (chọn). Không chọn giờ ở đây, giờ giao chung cho cả đơn chọn riêng
  /// ở phần "Hình thức giao".
  Future<void> _editScheduleDialog(CartItem item) async {
    var slots = [...item.deliverySlots];
    final theme = Theme.of(context);

    void toggleDay(int iso, StateSetter setInner) {
      if (slots.any((s) => s.weekday == iso)) {
        slots = slots.where((s) => s.weekday != iso).toList();
      } else {
        slots = [...slots, DeliverySlot(weekday: iso, time: _time)]
          ..sort(DeliverySlot.compare);
      }
      ref.read(cartProvider.notifier).updateDeliverySlots(item.lineId, slots);
      setState(() => _recurringConfirmed = false);
      setInner(() {});
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) {
          return AlertDialog(
            title: Text('Ngày giao cho "${item.productName}"'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _weekdayLabels.map((d) {
                  final selected = slots.any((s) => s.weekday == d.iso);
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => toggleDay(d.iso, setInner),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${d.label} (${_shortDate(_nearestFutureDate(d.iso))})',
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
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

  /// Toàn bộ ngày sẽ phát sinh đơn nếu xác nhận lặp lại [_weeks] tuần với lịch hiện tại
  /// (gộp các thứ mà tất cả sản phẩm đã chọn, mỗi thứ lặp lại theo đúng số tuần).
  List<DateTime> _recurringPreview(CartState cart) {
    final weekdays = <int>{};
    for (final item in cart.items) {
      for (final s in item.deliverySlots) {
        weekdays.add(s.weekday);
      }
    }
    if (weekdays.isEmpty) return [];
    final schedule = PreorderSchedule(
      slots: (weekdays.toList()..sort())
          .map((w) => DeliverySlot(weekday: w, time: _time))
          .toList(),
      recurring: true,
      weeks: _weeks,
    );
    return schedule.occurrences;
  }

  Future<void> _confirmRecurring(CartState cart) async {
    final occurrences = _recurringPreview(cart);
    if (occurrences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chọn ngày giao cho sản phẩm trước khi xác nhận'),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Giao lặp lại $_weeks tuần tới?'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bạn muốn giao đúng theo lịch dưới đây, phải không?',
                ),
                const SizedBox(height: 8),
                ...occurrences.map((d) => Text('• ${formatDateTime(d)}')),
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
    );
    if (confirm == true) setState(() => _recurringConfirmed = true);
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
    if (_mode == 'recurring' && !_recurringConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng xác nhận lịch giao lặp lại trước khi thanh toán',
          ),
        ),
      );
      return;
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

  Widget _itemCard(
    BuildContext context,
    CartItem item, {
    bool showSchedule = true,
  }) {
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
            if (showSchedule) ...[
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
          ],
        ),
      ),
    );
  }

  Widget _dayPicker(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    final viewDay = _selectedViewDay;
    final itemsForViewDay = (viewDay == null || !_weekInRange(_weekOffset))
        ? <CartItem>[]
        : cart.items
              .where((i) => i.deliverySlots.any((s) => s.weekday == viewDay))
              .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_mode == 'recurring' && _recurringConfirmed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_repeat,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Đang áp dụng lịch lặp lại $_weeks tuần tới',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            final hasAny =
                _weekInRange(_weekOffset) &&
                cart.items.any(
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
          if (!_weekInRange(_weekOffset))
            Text(
              _mode == 'once'
                  ? 'Ngoài phạm vi — "Giao 1 lần" chỉ áp dụng tuần gần nhất'
                  : 'Ngoài phạm vi lịch lặp lại ($_weeks tuần tới)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (itemsForViewDay.isEmpty)
            Text(
              'Chưa có món nào giao ngày này',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            ...itemsForViewDay.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.productName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${formatVnd(i.unitPrice + i.toppingsTotal)} x ${i.quantity}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatVnd(i.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng cộng ngày ${_weekdayLabelOf(viewDay)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  formatVnd(
                    itemsForViewDay.fold<int>(0, (sum, i) => sum + i.lineTotal),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tổng tuần', style: theme.textTheme.titleSmall),
            Text(
              formatVnd(_weekTotal(cart)),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Footer chung: tổng số món/tiền + nút thanh toán — dùng cho cả 2 tab, chỉ khác
  /// hành vi khi bấm "Đến thanh toán".
  Widget _footer(
    BuildContext context,
    CartState cart,
    VoidCallback onCheckout,
  ) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('Tổng số món'), Text('${cart.itemCount}')],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('Phí ship'), const Text('Miễn phí')],
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
                onPressed: onCheckout,
                child: const Text('Đến thanh toán'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab "Giá sỉ" — chỉ cần 1 ngày giao + 1 giờ giao chung cho cả đơn, không có ngày
  /// trong tuần / lặp lại như tab "Đặt trước".
  Widget _wholesaleTab(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    return Column(
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: cart.items
                .map((item) => _itemCard(context, item, showSchedule: false))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ngày giao', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _wholesaleDate == null
                      ? 'Chọn ngày giao'
                      : _shortDate(_wholesaleDate!),
                ),
                onPressed: _pickWholesaleDate,
              ),
              const SizedBox(height: 16),
              Text('Giờ giao', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time_outlined),
                label: Text('Giờ giao: ${_wholesaleTime.format(context)}'),
                onPressed: _pickWholesaleTime,
              ),
            ],
          ),
        ),
        _footer(context, cart, () => _goCheckoutWholesale(cart)),
      ],
    );
  }

  /// Tab "Đặt trước" — khung hiện tại: mỗi món tick ngày riêng trong tuần, xem lịch theo
  /// cột ngày bên phải, chọn giao 1 lần/nhiều lần.
  Widget _preorderTab(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    return Column(
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
                onPressed: () async {
                  await _pickTime();
                  setState(() => _recurringConfirmed = false);
                },
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
                    onSelected: (_) => setState(() {
                      _mode = 'once';
                      _recurringConfirmed = false;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Giao nhiều lần'),
                    selected: _mode == 'recurring',
                    onSelected: (_) => setState(() {
                      _mode = 'recurring';
                      _recurringConfirmed = false;
                    }),
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
                          ? () => setState(() {
                              _weeks--;
                              _recurringConfirmed = false;
                            })
                          : null,
                    ),
                    Text(
                      '$_weeks',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _weeks < 12
                          ? () => setState(() {
                              _weeks++;
                              _recurringConfirmed = false;
                            })
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: Icon(
                        _recurringConfirmed
                            ? Icons.check_circle
                            : Icons.event_available,
                      ),
                      label: Text(
                        _recurringConfirmed
                            ? 'Đã xác nhận'
                            : 'Xác nhận lịch giao',
                      ),
                      onPressed: () => _confirmRecurring(cart),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _footer(context, cart, () => _goCheckout(cart)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final isPreorderCart = !cart.isEmpty && cart.salesModel == 'scheduled';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt trước'),
        bottom: isPreorderCart
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Giá sỉ'),
                  Tab(text: 'Đặt trước'),
                ],
              )
            : null,
      ),
      body: !isPreorderCart
          ? const Center(
              child: Text('Chưa có sản phẩm đặt trước/bán sỉ nào trong giỏ'),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _wholesaleTab(context, cart),
                _preorderTab(context, cart),
              ],
            ),
    );
  }
}
