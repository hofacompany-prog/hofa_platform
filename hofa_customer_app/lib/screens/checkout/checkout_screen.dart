import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/address.dart';
import '../../models/cart_item.dart';
import '../../models/preorder_schedule.dart';
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
    if (widget.preorderSchedule != null &&
        !widget.preorderSchedule!.recurring) {
      _scheduledFor = widget.preorderSchedule!.earliestOccurrence;
    } else if (widget.initialScheduledFor != null) {
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

  Future<void> _placeOrder(Address address) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.merchantId == null || cart.branchId == null)
      return;
    final items = _relevantItems(cart);
    if (items.isEmpty) return;

    final schedule = widget.preorderSchedule;
    if (schedule != null && schedule.recurring) {
      await _placeRecurringOrders(cart, items, address, schedule);
      return;
    }

    setState(() => _placing = true);
    try {
      final order = await ref
          .read(orderRepoProvider)
          .createOrder(_orderBody(cart, items, address, _scheduledFor));
      await ref
          .read(cartProvider.notifier)
          .removeItems(items.map((i) => i.lineId).toList());
      if (mounted) context.go('/orders/${order.id}');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi đặt hàng: $e')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  /// Chưa có khái niệm "đơn lặp định kỳ" ở backend — giao nhiều lần nghĩa là tạo sẵn
  /// nhiều đơn độc lập, mỗi đơn ứng với 1 lần giao trong lịch đã chọn.
  Future<void> _placeRecurringOrders(
    CartState cart,
    List<CartItem> items,
    Address address,
    PreorderSchedule schedule,
  ) async {
    final occurrences = schedule.occurrences;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tạo ${occurrences.length} đơn hàng?'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: occurrences
                  .map((d) => Text('• ${formatDateTime(d)}'))
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

    setState(() => _placing = true);
    var created = 0;
    try {
      for (final occurrence in occurrences) {
        await ref
            .read(orderRepoProvider)
            .createOrder(_orderBody(cart, items, address, occurrence));
        created++;
      }
      await ref
          .read(cartProvider.notifier)
          .removeItems(items.map((i) => i.lineId).toList());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã tạo $created đơn hàng')));
        context.go('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tạo $created/${occurrences.length} đơn, lỗi: $e'),
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

    final itemsSubtotal = items.fold<int>(0, (sum, i) => sum + i.lineTotal);
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
                widget.preorderSchedule!.recurring
                    ? 'Giao lặp lại ${widget.preorderSchedule!.slots.length} khung giờ/tuần, trong ${widget.preorderSchedule!.weeks} tuần tới'
                    : 'Giao 1 lần: ${formatDateTime(_scheduledFor!)}',
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
