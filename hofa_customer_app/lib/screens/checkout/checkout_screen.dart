import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/address.dart';
import '../../models/cart_item.dart';
import '../../models/preorder_schedule.dart';
import '../../models/wholesale_tier.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/cart_provider.dart';
import '../address/address_picker_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final PreorderSchedule? preorderSchedule;

  /// Ngày+giờ giao đã chọn sẵn từ tab "Giá sỉ" (chỉ 1 lần giao, không lặp lại) — khác
  /// với [preorderSchedule] vốn dùng cho tab "Đặt trước" (theo thứ trong tuần).
  final DateTime? initialScheduledFor;
  const CheckoutScreen({
    super.key,
    this.preorderSchedule,
    this.initialScheduledFor,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _selectedAddressId;
  String _paymentMethod = 'cod';
  DateTime? _scheduledFor;
  final _voucherCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _voucherDiscount = 0;
  String? _voucherError;
  bool _voucherChecking = false;
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialScheduledFor != null) {
      _scheduledFor = widget.initialScheduledFor;
    }
  }

  @override
  void dispose() {
    _voucherCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Giỏ "đặt trước/bán sỉ" chứa lẫn món của cả tab Giá sỉ lẫn Đặt trước — đặt hàng từ
  /// tab nào chỉ được gửi/xoá đúng món của tab đó, không đụng tới món của tab còn lại.
  List<CartItem> _relevantItems(CartState cart) {
    if (cart.salesModel != 'scheduled') return cart.items;
    if (widget.initialScheduledFor != null) {
      return cart.items.where((i) => i.orderKind == 'wholesale').toList();
    }
    return cart.items.where((i) => i.orderKind == 'preorder').toList();
  }

  Future<void> _addAddress() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final line1Ctrl = TextEditingController();
    final wardCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final provinceCtrl = TextEditingController();
    double? pickedLat;
    double? pickedLng;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Thêm địa chỉ giao hàng'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên người nhận',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SĐT người nhận',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      pickedLat == null
                          ? 'Chọn vị trí trên bản đồ'
                          : 'Đã chọn vị trí trên bản đồ ✓',
                    ),
                    onPressed: () async {
                      final picked = await Navigator.of(context)
                          .push<PickedAddress>(
                            MaterialPageRoute(
                              builder: (_) => const AddressPickerScreen(),
                            ),
                          );
                      if (picked == null) return;
                      line1Ctrl.text = picked.line1;
                      wardCtrl.text = picked.ward ?? '';
                      districtCtrl.text = picked.district ?? '';
                      provinceCtrl.text = picked.province;
                      setDialogState(() {
                        pickedLat = picked.latitude;
                        pickedLng = picked.longitude;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: line1Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Số nhà, tên đường',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: wardCtrl,
                    decoration: const InputDecoration(labelText: 'Phường/Xã'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: districtCtrl,
                    decoration: const InputDecoration(labelText: 'Quận/Huyện'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: provinceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tỉnh/Thành phố',
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
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty ||
        phoneCtrl.text.trim().isEmpty ||
        line1Ctrl.text.trim().isEmpty ||
        provinceCtrl.text.trim().isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thiếu thông tin bắt buộc')),
        );
      return;
    }
    try {
      final created = await ref.read(userRepoProvider).createAddress({
        'recipient_name': nameCtrl.text.trim(),
        'recipient_phone': phoneCtrl.text.trim(),
        'line1': line1Ctrl.text.trim(),
        'ward': wardCtrl.text.trim().isEmpty ? null : wardCtrl.text.trim(),
        'district': districtCtrl.text.trim().isEmpty
            ? null
            : districtCtrl.text.trim(),
        'province': provinceCtrl.text.trim(),
        if (pickedLat != null) 'latitude': pickedLat,
        if (pickedLng != null) 'longitude': pickedLng,
      });
      ref.invalidate(addressesProvider);
      setState(() => _selectedAddressId = created.id);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _checkVoucher(String merchantId, int orderAmount) async {
    final code = _voucherCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _voucherChecking = true;
      _voucherError = null;
    });
    try {
      final res = await ref
          .read(voucherRepoProvider)
          .validate(
            code: code,
            merchantId: merchantId,
            orderAmount: orderAmount,
          );
      setState(() {
        _voucherDiscount = res.valid ? res.estimatedDiscount : 0;
        _voucherError = res.valid ? null : (res.reason ?? 'Mã không hợp lệ');
      });
    } catch (e) {
      setState(() {
        _voucherDiscount = 0;
        _voucherError = 'Lỗi kiểm tra mã: $e';
      });
    } finally {
      if (mounted) setState(() => _voucherChecking = false);
    }
  }

  Map<String, dynamic> _orderBody(
    CartState cart,
    List<CartItem> items,
    Address address,
    DateTime? scheduledFor,
  ) => {
    'merchant_id': cart.merchantId,
    'branch_id': cart.branchId,
    'sales_model': cart.salesModel,
    'items': items
        .map(
          (e) => {
            'variant_id': e.variantId,
            'quantity': e.quantity,
            // orderKind cho backend biết chỉ xét đúng loại bậc giá (giá sỉ/đặt trước) —
            // 1 biến thể có thể có cả 2 loại, không được lẫn giá của tab kia.
            if (e.orderKind != null) 'order_kind': e.orderKind,
            // Số ngày/tuần khách đặt RIÊNG món này — backend dùng để so bậc "đặt trước"
            // theo điều kiện số ngày (chỉ có ý nghĩa với món ở tab Đặt trước).
            if (e.deliverySlots.isNotEmpty)
              'days_count': e.deliverySlots.length,
            if (e.note != null) 'note': e.note,
            if (e.toppings.isNotEmpty)
              'topping_ids': e.toppings.map((t) => t.id).toList(),
          },
        )
        .toList(),
    'ship_recipient_name': address.recipientName,
    'ship_recipient_phone': address.recipientPhone,
    'ship_line1': address.line1,
    'ship_province': address.province,
    'ship_ward': address.ward,
    'ship_district': address.district,
    'ship_latitude': address.latitude,
    'ship_longitude': address.longitude,
    'payment_method': _paymentMethod,
    'delivery_fee': 0,
    if (_voucherDiscount > 0) 'voucher_code': _voucherCtrl.text.trim(),
    if (cart.salesModel == 'scheduled' && scheduledFor != null)
      'scheduled_for': scheduledFor.toIso8601String(),
    if (_noteCtrl.text.trim().isNotEmpty)
      'customer_note': _noteCtrl.text.trim(),
  };

  /// Gom món theo đúng lần giao (tab Đặt trước: mỗi thứ trong tuần chỉ giao đúng những
  /// món đã tick thứ đó, không gộp lẫn món của ngày khác vào cùng 1 đơn — quan trọng vì
  /// backend chốt bậc giá "đặt trước" theo TỔNG số lượng của cả đơn, gộp lẫn ngày khác
  /// vào sẽ làm sai tổng đó). Tab Giá sỉ chỉ có 1 lần giao duy nhất nên luôn ra đúng 1 đơn.
  List<MapEntry<DateTime, List<CartItem>>> _groupByOccurrence(
    List<CartItem> items,
  ) {
    final schedule = widget.preorderSchedule;
    if (schedule == null) {
      return [MapEntry(_scheduledFor ?? DateTime.now(), items)];
    }
    final result = <MapEntry<DateTime, List<CartItem>>>[];
    for (final occurrence in schedule.occurrences) {
      final dayItems = items
          .where(
            (i) => i.deliverySlots.any((s) => s.weekday == occurrence.weekday),
          )
          .toList();
      if (dayItems.isNotEmpty) result.add(MapEntry(occurrence, dayItems));
    }
    return result;
  }

  /// Bậc giá sỉ (minDaysPerWeek = 0) chỉ có điều kiện số lượng, so theo [ownQty] — số
  /// lượng riêng món này. Bậc đặt trước (minDaysPerWeek > 0) có 2 điều kiện độc lập: số
  /// lượng so theo [orderQty] (tổng số lượng cả đơn) và số ngày/tuần so theo [daysCount]
  /// (số ngày/tuần riêng món này) — đạt điều kiện nào lấy giá tương ứng, đúng như
  /// resolve_variant_price() phía backend, để giá xem trước ở đây khớp với giá thực chốt.
  int _matchedTierPrice(
    int ownQty,
    int orderQty,
    int daysCount,
    int fallback,
    List<WholesaleTier> tiers,
  ) {
    bool qtyMet(WholesaleTier t) {
      final ref = t.minDaysPerWeek == 0 ? ownQty : orderQty;
      return ref >= t.minQuantity &&
          (t.maxQuantity == null || ref <= t.maxQuantity!);
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

  /// Xem trước tổng tiền — mỗi lần giao (đơn) tính riêng theo đúng tổng số lượng của
  /// CHÍNH đơn đó, khớp với cách backend chốt giá khi thực sự tạo đơn.
  int _tierAwareSubtotal(List<MapEntry<DateTime, List<CartItem>>> orders) {
    var total = 0;
    for (final entry in orders) {
      final dayItems = entry.value;
      final orderQty = dayItems.fold<int>(0, (sum, i) => sum + i.quantity);
      for (final i in dayItems) {
        // Đơn "đặt trước" chỉ được xét bậc đặt trước (minDaysPerWeek > 0) — biến thể có
        // thể có cả bậc giá sỉ, không được lẫn giá của loại kia vào đây.
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
                orderQty,
                i.deliverySlots.length,
                i.basePrice,
                tiers,
              );
        total += (price + i.toppingsTotal) * i.quantity;
      }
    }
    return total;
  }

  Future<void> _placeOrder(Address address) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.merchantId == null || cart.branchId == null)
      return;
    final items = _relevantItems(cart);
    if (items.isEmpty) return;

    final orders = _groupByOccurrence(items);
    if (orders.isEmpty) return;

    if (orders.length > 1) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Tạo ${orders.length} đơn hàng?'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: orders
                    .map(
                      (e) => Text(
                        '• ${formatDateTime(e.key)} (${e.value.length} món)',
                      ),
                    )
                    .toList(),
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
      if (confirm != true) return;
    }

    setState(() => _placing = true);
    var created = 0;
    String? lastOrderId;
    try {
      for (final entry in orders) {
        final order = await ref
            .read(orderRepoProvider)
            .createOrder(_orderBody(cart, entry.value, address, entry.key));
        lastOrderId = order.id;
        created++;
      }
      await ref
          .read(cartProvider.notifier)
          .removeItems(items.map((i) => i.lineId).toList());
      if (mounted) {
        if (orders.length > 1) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Đã tạo $created đơn hàng')));
          context.go('/orders');
        } else {
          context.go('/orders/$lastOrderId');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: orders.length > 1
                ? Text('Đã tạo $created/${orders.length} đơn, lỗi: $e')
                : Text('Lỗi đặt hàng: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesProvider);
    final theme = Theme.of(context);
    final items = _relevantItems(cart);

    if (items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Giỏ hàng trống')),
      );
    }

    final scheduledOrders = widget.preorderSchedule != null
        ? _groupByOccurrence(items)
        : null;
    final itemsSubtotal = scheduledOrders != null
        ? _tierAwareSubtotal(scheduledOrders)
        : items.fold<int>(0, (sum, i) => sum + i.lineTotal);
    final total = itemsSubtotal - _voucherDiscount;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Thanh toán'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Địa chỉ giao hàng', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          addressesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Lỗi: $e'),
            data: (addresses) {
              if (_selectedAddressId == null && addresses.isNotEmpty) {
                final defaultAddr = addresses
                    .where((a) => a.isDefault)
                    .toList();
                _selectedAddressId = defaultAddr.isNotEmpty
                    ? defaultAddr.first.id
                    : addresses.first.id;
              }
              return Column(
                children: [
                  RadioGroup<String>(
                    groupValue: _selectedAddressId,
                    onChanged: (v) => setState(() => _selectedAddressId = v),
                    child: Column(
                      children: addresses
                          .map(
                            (a) => RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: a.id,
                              title: Text(
                                '${a.recipientName} · ${a.recipientPhone}',
                              ),
                              subtitle: Text(a.fullLine),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addAddress,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm địa chỉ mới'),
                    ),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          Text('Mã giảm giá', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _voucherCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Nhập mã voucher',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _voucherChecking
                    ? null
                    : () => _checkVoucher(cart.merchantId!, itemsSubtotal),
                child: _voucherChecking
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Áp dụng'),
              ),
            ],
          ),
          if (_voucherError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _voucherError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_voucherDiscount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Giảm ${formatVnd(_voucherDiscount)}',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          const Divider(height: 32),
          Text('Phương thức thanh toán', style: theme.textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: _paymentMethod,
            onChanged: (v) =>
                setState(() => _paymentMethod = v ?? _paymentMethod),
            child: Column(
              children: const [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'cod',
                  title: Text('Thanh toán khi nhận hàng (COD)'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'bank_transfer',
                  title: Text('Chuyển khoản ngân hàng'),
                ),
              ],
            ),
          ),
          if (cart.salesModel == 'scheduled') ...[
            const Divider(height: 32),
            Text('Lịch giao', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (widget.preorderSchedule != null) ...[
              Text(
                (scheduledOrders?.length ?? 0) > 1
                    ? 'Sẽ tạo ${scheduledOrders!.length} đơn hàng riêng, mỗi đơn đúng món của lần giao đó'
                    : 'Giao 1 lần: ${formatDateTime(scheduledOrders!.first.key)}',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa lịch giao'),
                ),
              ),
            ] else if (widget.initialScheduledFor != null) ...[
              Text('Giao: ${formatDateTime(_scheduledFor!)}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa lịch giao'),
                ),
              ),
            ] else
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _scheduledFor == null
                      ? 'Chọn ngày'
                      : formatDate(_scheduledFor!),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 2)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) setState(() => _scheduledFor = picked);
                },
              ),
          ],
          const Divider(height: 32),
          Text('Ghi chú cho cửa hàng', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              hintText: 'Không bắt buộc',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [const Text('Tạm tính'), Text(formatVnd(itemsSubtotal))],
          ),
          if (_voucherDiscount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Giảm giá'),
                  Text('-${formatVnd(_voucherDiscount)}'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tổng cộng',
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
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_placing || _selectedAddressId == null)
                ? null
                : () {
                    final addresses = addressesAsync.valueOrNull ?? [];
                    final address = addresses
                        .where((a) => a.id == _selectedAddressId)
                        .toList();
                    if (address.isEmpty) return;
                    _placeOrder(address.first);
                  },
            child: _placing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Đặt hàng'),
          ),
        ],
      ),
    );
  }
}
