import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/cart_item.dart';
import '../../models/delivery_slot.dart';
import '../../models/preorder_schedule.dart';
import '../../models/wholesale_tier.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/topping_picker_dialog.dart';

/// Màu cam thương hiệu (accent) — dùng để làm nổi bật giá khi đã đổi khỏi giá mặc định
/// theo bậc giá sỉ/đặt trước.
const _accentColor = Color(0xFFFB8519);

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

  /// Cách tính "Tổng tiền" ở tab Đặt trước — 'day': tính 1 lần giao (giống Giá sỉ),
  /// 'week': cộng dồn theo số ngày mỗi món giao trong tuần (giống Tổng tuần).
  String _totalBasis = 'day';

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

  void _goCheckoutWholesale(List<CartItem> items) {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có sản phẩm giá sỉ nào trong giỏ')),
      );
      return;
    }
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

  /// Tổng tiền của cả tuần đang xem — cộng dồn theo TỪNG ngày (mỗi ngày tự chốt bậc giá
  /// theo tổng số phần của riêng ngày đó, gộp mọi món), rồi cộng các ngày lại.
  int _weekTotal(List<CartItem> items) {
    if (!_weekInRange(_weekOffset)) return 0;
    var total = 0;
    for (final d in _weekdayLabels) {
      final dayItems = items
          .where((i) => i.deliverySlots.any((s) => s.weekday == d.iso))
          .toList();
      if (dayItems.isEmpty) continue;
      final dayQty = dayItems.fold<int>(0, (sum, i) => sum + i.quantity);
      for (final i in dayItems) {
        // Đặt trước chỉ xét bậc đặt trước (minDaysPerWeek > 0) — biến thể có thể có cả
        // bậc giá sỉ, không được lẫn giá của tab kia.
        final tiers =
            ref
                .watch(wholesaleTiersProvider(i.variantId))
                .valueOrNull
                ?.where((t) => t.minDaysPerWeek > 0)
                .toList() ??
            const <WholesaleTier>[];
        final price = tiers.isEmpty
            ? i.basePrice
            : _matchedTierPrice(
                i.quantity,
                dayQty,
                i.deliverySlots.length,
                i.basePrice,
                tiers,
              );
        total += (price + i.toppingsTotal) * i.quantity;
      }
    }
    return total;
  }

  /// Tổng "tính theo ngày" — mỗi món tính 1 lần theo giá bậc TỐT NHẤT có thể đạt được
  /// (giống hệt giá xem trước ở từng thẻ sản phẩm), không phải giá gốc lưu tạm lúc thêm
  /// vào giỏ — tránh lệch với giá đang hiển thị trên từng món.
  int _flatTotal(List<CartItem> items) => items.fold(0, (sum, i) {
    final price =
        _bestPreorderPrice(i, items) ??
        _bestWholesalePrice(i, items) ??
        i.unitPrice;
    return sum + (price + i.toppingsTotal) * i.quantity;
  });

  /// Giá sỉ: giá bậc tốt nhất đạt được, xét CẢ 2 điều kiện của bậc giá sỉ — số lượng
  /// riêng món này VÀ (nếu bậc có cấu hình min_order_quantity) tổng số lượng CẢ đơn giá
  /// sỉ (gộp mọi món trong [allItems]) — đúng như resolve_variant_price() phía backend.
  /// Trả về null nếu món này không thuộc tab Giá sỉ hoặc biến thể không có bậc giá sỉ nào.
  int? _bestWholesalePrice(CartItem item, List<CartItem> allItems) {
    if (item.orderKind != 'wholesale') return null;
    final tiers =
        ref
            .watch(wholesaleTiersProvider(item.variantId))
            .valueOrNull
            ?.where((t) => t.minDaysPerWeek == 0)
            .toList() ??
        const <WholesaleTier>[];
    if (tiers.isEmpty) return null;
    final orderQty = allItems.fold<int>(0, (sum, i) => sum + i.quantity);
    return _matchedTierPrice(item.quantity, orderQty, 0, item.basePrice, tiers);
  }

  /// Đặt trước: giá bậc tốt nhất có thể đạt được trong số các ngày món này đã chọn (ngày
  /// nào có tổng số phần cả nhóm cao nhất) — chỉ xét bậc đặt trước (minDaysPerWeek > 0),
  /// không lẫn giá bậc giá sỉ. Điều kiện số ngày/tuần so theo TỔNG số ngày khác nhau của
  /// CẢ ĐƠN (gộp lịch giao của mọi sản phẩm trong [allItems]), không phải riêng số ngày
  /// của món này — đặt món A thứ 2, món B thứ 4 thì cả 2 món đều tính đơn có 2 ngày/tuần.
  /// Trả về null nếu món này không thuộc tab Đặt trước hoặc biến thể không có bậc đặt
  /// trước nào (khi đó dùng giá gốc/giá sỉ như bình thường).
  int? _bestPreorderPrice(CartItem item, List<CartItem> allItems) {
    if (item.orderKind != 'preorder' || item.deliverySlots.isEmpty) {
      return null;
    }
    final preorderTiers =
        ref
            .watch(wholesaleTiersProvider(item.variantId))
            .valueOrNull
            ?.where((t) => t.minDaysPerWeek > 0)
            .toList() ??
        const <WholesaleTier>[];
    if (preorderTiers.isEmpty) return null;
    var bestOrderQty = 0;
    for (final weekday in item.deliverySlots.map((s) => s.weekday).toSet()) {
      final dayQty = allItems
          .where((i) => i.deliverySlots.any((s) => s.weekday == weekday))
          .fold<int>(0, (sum, i) => sum + i.quantity);
      if (dayQty > bestOrderQty) bestOrderQty = dayQty;
    }
    final orderDaysCount = allItems
        .expand((i) => i.deliverySlots.map((s) => s.weekday))
        .toSet()
        .length;
    return _matchedTierPrice(
      item.quantity,
      bestOrderQty,
      orderDaysCount,
      item.basePrice,
      preorderTiers,
    );
  }

  /// Bậc giá sỉ (minDaysPerWeek = 0) chỉ có điều kiện số lượng, so theo [ownQty] — số
  /// lượng riêng món này. Bậc đặt trước (minDaysPerWeek > 0) có 2 điều kiện độc lập: số
  /// lượng so theo [orderQty] (tổng số lượng cả lần giao, gộp mọi món) và số ngày/tuần so
  /// theo [daysCount] (tổng số ngày khác nhau của CẢ ĐƠN, gộp mọi món — không phải riêng
  /// món này) — đạt điều kiện nào lấy giá tương ứng, đúng như resolve_variant_price() phía
  /// backend chốt giá thật.
  int _matchedTierPrice(
    int ownQty,
    int orderQty,
    int daysCount,
    int fallback,
    List<WholesaleTier> tiers,
  ) {
    bool qtyMet(WholesaleTier t) {
      final ref = t.minDaysPerWeek == 0 ? ownQty : orderQty;
      final ownMet =
          ref >= t.minQuantity &&
          (t.maxQuantity == null || ref <= t.maxQuantity!);
      // Bậc giá sỉ có thêm điều kiện THAY THẾ theo tổng số lượng cả đơn — đạt 1 trong 2
      // là được giá bậc này, đúng như resolve_variant_price() phía backend.
      final orderQtyMet =
          t.minDaysPerWeek == 0 &&
          t.minOrderQuantity != null &&
          orderQty >= t.minOrderQuantity!;
      return ownMet || orderQtyMet;
    }

    bool daysMet(WholesaleTier t) =>
        t.minDaysPerWeek > 0 && daysCount >= t.minDaysPerWeek;

    final candidates = tiers.where((t) => qtyMet(t) || daysMet(t)).toList()
      ..sort(
        (a, b) => a.minQuantity != b.minQuantity
            ? b.minQuantity.compareTo(a.minQuantity)
            : b.minDaysPerWeek.compareTo(a.minDaysPerWeek),
      );
    if (candidates.isEmpty) return fallback;
    final t = candidates.first;
    if (qtyMet(t) && daysMet(t)) return t.unitPriceBoth ?? t.unitPrice;
    if (qtyMet(t)) return t.unitPrice;
    return t.unitPriceDays ?? t.unitPrice;
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

  /// Dùng chung cho cả nút xoá món lẫn giảm số lượng về 0 — tránh xoá nhầm khi lỡ tay bấm.
  Future<bool> _confirmDeleteItem(CartItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá sản phẩm?'),
        content: Text('Xoá "${item.productName}" khỏi giỏ hàng?'),
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
    return confirm == true;
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
      initialNote: item.note,
    );
    if (result != null) {
      await ref
          .read(cartProvider.notifier)
          .updateToppings(item.lineId, result.toppings, note: result.note);
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
  List<DateTime> _recurringPreview(List<CartItem> items) {
    final weekdays = <int>{};
    for (final item in items) {
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

  Future<void> _confirmRecurring(List<CartItem> items) async {
    final occurrences = _recurringPreview(items);
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

  void _goCheckout(List<CartItem> items) {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có sản phẩm đặt trước nào trong giỏ'),
        ),
      );
      return;
    }
    for (final item in items) {
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
    for (final item in items) {
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
    List<CartItem> allItems = const [],
  }) {
    final theme = Theme.of(context);
    final toppingGroups =
        ref.watch(toppingGroupsProvider(item.productId)).valueOrNull ?? [];
    final hasToppings = toppingGroups.isNotEmpty;
    final sortedSlots = [...item.deliverySlots]..sort(DeliverySlot.compare);
    // Giá sỉ tính lại đơn giá theo bậc giá cửa hàng đã cài mỗi khi đổi số lượng — chỉ xét
    // bậc giá sỉ (minDaysPerWeek = 0), biến thể có thể có cả bậc đặt trước, không được
    // lẫn giá của tab kia vào đây.
    final wholesaleTiers = item.orderKind == 'wholesale'
        ? ref
                  .watch(wholesaleTiersProvider(item.variantId))
                  .valueOrNull
                  ?.where((t) => t.minDaysPerWeek == 0)
                  .toList() ??
              const <WholesaleTier>[]
        : const <WholesaleTier>[];
    Future<void> changeQuantity(int quantity) async {
      if (quantity <= 0) {
        final confirmed = await _confirmDeleteItem(item);
        if (!confirmed) return;
      }
      // Tổng số lượng cả đơn giá sỉ SAU khi đổi số lượng món này — dùng cho điều kiện
      // thay thế min_order_quantity (xem _matchedTierPrice), không phải chỉ số lượng
      // riêng món này.
      final orderQtyAfterChange = allItems.fold<int>(
        0,
        (sum, i) => sum + (i.lineId == item.lineId ? quantity : i.quantity),
      );
      ref
          .read(cartProvider.notifier)
          .updateQuantity(
            item.lineId,
            quantity,
            // Không đạt bậc nào thì quay về giá gốc (basePrice), không phải giá bậc lần
            // trước còn lưu lại.
            unitPrice: wholesaleTiers.isEmpty
                ? null
                : _matchedTierPrice(
                    quantity,
                    orderQtyAfterChange,
                    0,
                    item.basePrice,
                    wholesaleTiers,
                  ),
          );
    }

    final preorderPrice = _bestPreorderPrice(item, allItems);
    final wholesalePrice = _bestWholesalePrice(item, allItems);
    // So với giá gốc (basePrice), không phải unitPrice — unitPrice bên Giá sỉ đã bị ghi
    // đè thành giá theo bậc mỗi khi đổi số lượng nên không còn phản ánh giá "mặc định".
    // Không đạt bậc nào thì preorderPrice/wholesalePrice tự trả về basePrice.
    final displayPrice = preorderPrice ?? wholesalePrice ?? item.unitPrice;
    final discounted = displayPrice != item.basePrice;

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
                        '${formatVnd(displayPrice + item.toppingsTotal)}'
                        '${discounted ? ' (Giá sỉ)' : ''}',
                        style: TextStyle(
                          color: discounted
                              ? _accentColor
                              : theme.colorScheme.primary,
                          fontWeight: discounted ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (!await _confirmDeleteItem(item)) return;
                    ref.read(cartProvider.notifier).removeItem(item.lineId);
                  },
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
                  onPressed: () => changeQuantity(item.quantity - 1),
                ),
                Text('${item.quantity}'),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => changeQuantity(item.quantity + 1),
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

  Widget _dayPicker(BuildContext context, List<CartItem> items) {
    final theme = Theme.of(context);
    final viewDay = _selectedViewDay;
    final itemsForViewDay = (viewDay == null || !_weekInRange(_weekOffset))
        ? <CartItem>[]
        : items
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
                items.any(
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
            () {
              // Bậc "đặt trước" chốt theo TỔNG số phần của cả ngày này (gộp mọi món),
              // không phân biệt sản phẩm — khớp với cách backend chốt giá thật.
              final dayQty = itemsForViewDay.fold<int>(
                0,
                (sum, i) => sum + i.quantity,
              );
              int priceFor(CartItem i) {
                // Chỉ xét bậc đặt trước (minDaysPerWeek > 0) — biến thể có thể có cả bậc
                // giá sỉ, không được lẫn giá của tab kia.
                final tiers =
                    ref
                        .watch(wholesaleTiersProvider(i.variantId))
                        .valueOrNull
                        ?.where((t) => t.minDaysPerWeek > 0)
                        .toList() ??
                    const <WholesaleTier>[];
                return tiers.isEmpty
                    ? i.basePrice
                    : _matchedTierPrice(
                        i.quantity,
                        dayQty,
                        i.deliverySlots.length,
                        i.basePrice,
                        tiers,
                      );
              }

              int lineTotalFor(CartItem i) =>
                  (priceFor(i) + i.toppingsTotal) * i.quantity;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Builder(
                                  builder: (context) {
                                    final price = priceFor(i);
                                    final discounted = price != i.basePrice;
                                    return Text(
                                      '${formatVnd(price + i.toppingsTotal)} x ${i.quantity}'
                                      '${discounted ? ' (Giá sỉ)' : ''}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: discounted
                                                ? _accentColor
                                                : null,
                                            fontWeight: discounted
                                                ? FontWeight.w600
                                                : null,
                                          ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatVnd(lineTotalFor(i)),
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
                          itemsForViewDay.fold<int>(
                            0,
                            (sum, i) => sum + lineTotalFor(i),
                          ),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }(),
          ],
        ],
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tổng tuần', style: theme.textTheme.titleSmall),
            Text(
              formatVnd(_weekTotal(items)),
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

  /// Footer chung: tổng số món/tiền + nút thanh toán — dùng cho cả 2 tab, mỗi tab tự
  /// tính [total] riêng (Giá sỉ luôn tính đơn giản, Đặt trước tính theo ngày hoặc tuần
  /// tuỳ [_totalBasis]) và tự quyết hành vi khi bấm "Đến thanh toán".
  Widget _footer(
    BuildContext context,
    int itemCount,
    int total,
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
              children: [const Text('Tổng số món'), Text('$itemCount')],
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
                  formatVnd(total),
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
    final items = cart.items.where((i) => i.orderKind == 'wholesale').toList();
    final itemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
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
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Chưa có sản phẩm giá sỉ nào trong giỏ',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: items
                      .map(
                        (item) => _itemCard(
                          context,
                          item,
                          showSchedule: false,
                          allItems: items,
                        ),
                      )
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
        _footer(
          context,
          itemCount,
          _flatTotal(items),
          () => _goCheckoutWholesale(items),
        ),
      ],
    );
  }

  /// Tab "Đặt trước" — khung hiện tại: mỗi món tick ngày riêng trong tuần, xem lịch theo
  /// cột ngày bên phải, chọn giao 1 lần/nhiều lần.
  Widget _preorderTab(BuildContext context, CartState cart) {
    final theme = Theme.of(context);
    final items = cart.items.where((i) => i.orderKind == 'preorder').toList();
    final itemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
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
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Chưa có sản phẩm đặt trước nào trong giỏ',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                        children: items
                            .map(
                              (item) =>
                                  _itemCard(context, item, allItems: items),
                            )
                            .toList(),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _dayPicker(context, items)),
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
                      onPressed: () => _confirmRecurring(items),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Cách tính tổng tiền', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tính theo ngày'),
                    selected: _totalBasis == 'day',
                    onSelected: (_) => setState(() => _totalBasis = 'day'),
                  ),
                  ChoiceChip(
                    label: const Text('Tính theo tuần'),
                    selected: _totalBasis == 'week',
                    onSelected: (_) => setState(() => _totalBasis = 'week'),
                  ),
                ],
              ),
            ],
          ),
        ),
        _footer(
          context,
          itemCount,
          _totalBasis == 'week' ? _weekTotal(items) : _flatTotal(items),
          () => _goCheckout(items),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final isPreorderCart = !cart.isEmpty && cart.salesModel == 'scheduled';
    final wholesaleCount = cart.items
        .where((i) => i.orderKind == 'wholesale')
        .fold<int>(0, (sum, i) => sum + i.quantity);
    final preorderItemCount = cart.items
        .where((i) => i.orderKind == 'preorder')
        .fold<int>(0, (sum, i) => sum + i.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt trước'),
        bottom: isPreorderCart
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(child: _tabLabel('Giá sỉ', wholesaleCount)),
                  Tab(child: _tabLabel('Đặt trước', preorderItemCount)),
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

  /// Nhãn tab kèm vòng tròn số món — giống hệt cách hiển thị ở thanh điều hướng dưới, chỉ
  /// đẩy lệch ra ngoài/lên cao hơn một chút để không đè lên chữ (khác Icon vuông vắn của
  /// thanh điều hướng, Text dài ngắn khác nhau nên vòng tròn dễ che chữ nếu để mặc định).
  Widget _tabLabel(String text, int count) => count > 0
      ? Badge(
          offset: const Offset(12, -20),
          label: Text('$count'),
          child: Text(text),
        )
      : Text(text);
}
