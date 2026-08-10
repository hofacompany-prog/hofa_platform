import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../models/address.dart';
import '../../models/buy_now_request.dart';
import '../../models/cart_item.dart';
import '../../models/merchant_fee_tier.dart';
import '../../models/preorder_schedule.dart';
import '../../models/voucher.dart';
import '../../models/wholesale_tier.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/cart_provider.dart';
import '../../models/available_driver.dart';
import '../../widgets/buy_on_behalf_fee_notice.dart';
import '../../widgets/driver_picker_dialog.dart';
import '../../widgets/voucher_picker_dialog.dart';
import '../address/address_picker_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final PreorderSchedule? preorderSchedule;

  /// Ngày+giờ giao đã chọn sẵn từ tab "Giá sỉ" (chỉ 1 lần giao, không lặp lại) — khác
  /// với [preorderSchedule] vốn dùng cho tab "Đặt trước" (theo thứ trong tuần).
  final DateTime? initialScheduledFor;

  /// Có giá trị khi vào từ nút "Mua ngay" ở trang chi tiết sản phẩm — thanh toán CHỈ tính
  /// tiền cho đúng sản phẩm này, không đọc/không đụng tới giỏ hàng chung (cartProvider),
  /// giữ nguyên mọi món khách đã bỏ vào giỏ trước đó.
  final BuyNowRequest? buyNowRequest;
  const CheckoutScreen({
    super.key,
    this.preorderSchedule,
    this.initialScheduledFor,
    this.buyNowRequest,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _selectedAddressId;
  bool _autoFindDriver = true;
  AvailableDriver? _selectedDriver;
  String _paymentMethod = 'cod';
  DateTime? _scheduledFor;
  final _noteCtrl = TextEditingController();
  // Nhiều voucher cùng lúc, tối đa theo voucherMaxCountProvider (admin cấu hình).
  final List<_AppliedVoucher> _appliedVouchers = [];
  String? _voucherError;
  bool _voucherChecking = false;
  bool _placing = false;
  String? _driverPickError;

  int get _voucherDiscount =>
      _appliedVouchers.fold(0, (sum, v) => sum + v.discount);

  @override
  void initState() {
    super.initState();
    if (widget.initialScheduledFor != null) {
      _scheduledFor = widget.initialScheduledFor;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Giỏ ảo chỉ chứa đúng 1 món của [BuyNowRequest] — không đọc/không ghi cartProvider,
  /// dùng để tái sử dụng toàn bộ logic tính tiền/đặt đơn của màn này mà không đụng tới
  /// giỏ hàng thật của khách.
  CartState _buyNowCart(BuyNowRequest req) => CartState(
    merchantId: req.merchantId,
    merchantName: req.merchantName,
    branchId: req.branchId,
    salesModel: req.salesModel,
    items: [req.item],
  );

  /// Giỏ "đặt trước/bán sỉ" chứa lẫn món của cả tab Giá sỉ lẫn Đặt trước — đặt hàng từ
  /// tab nào chỉ được gửi/xoá đúng món của tab đó, không đụng tới món của tab còn lại.
  /// Giỏ "Mua ngay" luôn chỉ có đúng 1 món cần thanh toán nên bỏ qua bộ lọc theo tab.
  List<CartItem> _relevantItems(CartState cart) {
    if (widget.buyNowRequest != null) return cart.items;
    if (cart.salesModel != 'scheduled') return cart.items;
    if (widget.initialScheduledFor != null) {
      return cart.items.where((i) => i.orderKind == 'wholesale').toList();
    }
    return cart.items.where((i) => i.orderKind == 'preorder').toList();
  }

  /// Phí ship tới địa chỉ ĐANG CHỌN — tự tính lại mỗi khi đổi địa chỉ vì đọc thẳng
  /// [_selectedAddressId] hiện tại. Đây là số THẬT được cộng vào "Tổng cộng" và gửi lên
  /// server lúc tạo đơn (_orderBody) — server tự chốt lại total_amount, không tin số
  /// client gửi mù quáng, nhưng CHƯA tự kiểm tra khoảng cách thật (xem README/ghi chú ở
  /// PR). Trả về null nếu chưa đủ dữ liệu để tính (chưa chọn địa chỉ, thiếu toạ độ...).
  int? _estimatedShippingFee(
    CartState cart,
    List<Address> addresses,
    int orderAmount,
  ) {
    final branchId = cart.branchId;
    if (branchId == null || _selectedAddressId == null) return null;
    final settings = ref.watch(shippingFeeSettingsProvider).valueOrNull;
    if (settings == null) return null;
    final branch = ref.watch(branchDetailProvider(branchId)).valueOrNull;
    if (branch == null || branch.latitude == null || branch.longitude == null) {
      return null;
    }
    final address = addresses.where((a) => a.id == _selectedAddressId).toList();
    if (address.isEmpty ||
        address.first.latitude == null ||
        address.first.longitude == null) {
      return null;
    }
    final distanceKm = haversineKm(
      branch.latitude!,
      branch.longitude!,
      address.first.latitude!,
      address.first.longitude!,
    );
    return settings.estimate(distanceKm, orderAmount: orderAmount);
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

  /// Kiểm tra + thêm 1 mã vào danh sách voucher đã áp dụng (không thay thế mã cũ) — chặn
  /// thêm nếu mã đã có trong danh sách hoặc đã đạt số lượng tối đa (giới hạn thật vẫn nằm
  /// ở server lúc tạo đơn, đây chỉ để báo sớm cho khách).
  Future<void> _checkVoucher(
    String code,
    String merchantId,
    int orderAmount,
    int deliveryFee,
  ) async {
    if (code.isEmpty) return;
    if (_appliedVouchers.any(
      (v) => v.code.toUpperCase() == code.toUpperCase(),
    )) {
      setState(() => _voucherError = 'Mã "$code" đã được áp dụng rồi');
      return;
    }
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
            deliveryFee: deliveryFee,
          );
      setState(() {
        if (res.valid) {
          _appliedVouchers.add(
            _AppliedVoucher(code: code, discount: res.estimatedDiscount),
          );
        } else {
          _voucherError = res.reason ?? 'Mã không hợp lệ';
        }
      });
    } catch (e) {
      setState(() => _voucherError = 'Lỗi kiểm tra mã: $e');
    } finally {
      if (mounted) setState(() => _voucherChecking = false);
    }
  }

  /// Mở popup chọn voucher công khai/nhập mã riêng, rồi kiểm tra + thêm vào danh sách mã
  /// đã áp dụng — dùng lại đúng _checkVoucher như lúc gõ tay, không tự tính giảm giá ở đây.
  Future<void> _pickVoucher(
    List<Voucher> publicVouchers,
    String merchantId,
    int orderAmount,
    int deliveryFee,
  ) async {
    final code = await showVoucherPickerDialog(
      context,
      vouchers: publicVouchers,
      orderAmount: orderAmount,
      excludeCodes: _appliedVouchers.map((v) => v.code).toList(),
    );
    if (code == null || code.isEmpty) return;
    await _checkVoucher(code, merchantId, orderAmount, deliveryFee);
  }

  void _removeVoucher(String code) {
    setState(() {
      _appliedVouchers.removeWhere((v) => v.code == code);
      _voucherError = null;
    });
  }

  /// Cửa hàng mua hộ bắt buộc chuyển khoản trước, không cho chọn COD — xem BuyOnBehalfFeeNotice
  /// (cảnh báo hiện sẵn ở màn cửa hàng/sản phẩm) và chặn lại lần nữa ở server (routes/orders.js).
  String _effectivePaymentMethod(CartState cart) {
    final merchant = cart.merchantId == null ? null : ref.read(merchantDetailProvider(cart.merchantId!)).valueOrNull;
    if (merchant?.isBuyOnBehalf == true) return 'bank_transfer';
    return _paymentMethod;
  }

  /// Tổng số ngày/tuần KHÁC NHAU của cả đơn đặt trước — gộp lịch giao của MỌI sản phẩm
  /// trong [items] (không phải riêng từng món) — dùng để so điều kiện bậc giá "đặt trước"
  /// (wholesale_tiers.min_days_per_week), khớp đúng cách preorder_screen tính giá xem
  /// trước và cách backend chốt giá thật.
  int _orderDaysCount(List<CartItem> items) =>
      items.expand((i) => i.deliverySlots.map((s) => s.weekday)).toSet().length;

  Map<String, dynamic> _orderBody(
    CartState cart,
    List<CartItem> items,
    Address address,
    DateTime? scheduledFor,
    int deliveryFee,
    int orderDaysCount,
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
            // Tổng số ngày/tuần KHÁC NHAU của CẢ ĐƠN (gộp mọi sản phẩm, không phải riêng
            // món này) — backend dùng để so bậc "đặt trước" theo điều kiện số ngày.
            if (e.deliverySlots.isNotEmpty)
              'days_count': orderDaysCount,
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
    'payment_method': _effectivePaymentMethod(cart),
    if (!_autoFindDriver && _selectedDriver != null) 'selected_driver_id': _selectedDriver!.id,
    'delivery_fee': deliveryFee,
    if (_appliedVouchers.isNotEmpty)
      'voucher_codes': _appliedVouchers.map((v) => v.code).toList(),
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
  /// (tổng số ngày khác nhau của CẢ ĐƠN, gộp mọi món — không phải riêng món này) — đạt
  /// điều kiện nào lấy giá tương ứng, đúng như resolve_variant_price() phía backend, để
  /// giá xem trước ở đây khớp với giá thực chốt.
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

  /// Xem trước tổng tiền — mỗi lần giao (đơn) tính riêng theo đúng tổng số lượng của
  /// CHÍNH đơn đó, khớp với cách backend chốt giá khi thực sự tạo đơn. Dùng chung cho cả
  /// tab Đặt trước (mỗi entry là 1 ngày trong tuần, chỉ xét bậc đặt trước) và tab Giá sỉ
  /// (đúng 1 entry gồm mọi món, chỉ xét bậc giá sỉ — xem _groupByOccurrence khi
  /// preorderSchedule null) — items trong 1 entry luôn cùng 1 orderKind, không lẫn lộn
  /// (xem _relevantItems).
  int _tierAwareSubtotal(
    List<MapEntry<DateTime, List<CartItem>>> orders,
    int orderDaysCount,
  ) {
    var total = 0;
    for (final entry in orders) {
      final dayItems = entry.value;
      final orderQty = dayItems.fold<int>(0, (sum, i) => sum + i.quantity);
      for (final i in dayItems) {
        final isWholesale = i.orderKind == 'wholesale';
        final tiers =
            ref
                .watch(wholesaleTiersProvider(i.variantId))
                .valueOrNull
                ?.where(
                  (t) => isWholesale
                      ? t.minDaysPerWeek == 0
                      : t.minDaysPerWeek > 0,
                )
                .toList() ??
            const <WholesaleTier>[];
        final price = tiers.isEmpty
            ? i.basePrice
            : _matchedTierPrice(
                i.quantity,
                orderQty,
                orderDaysCount,
                i.basePrice,
                tiers,
              );
        total += (price + i.toppingsTotal) * i.quantity;
      }
    }
    return total;
  }

  Future<void> _placeOrder(Address address, int deliveryFee) async {
    final cart = widget.buyNowRequest != null
        ? _buyNowCart(widget.buyNowRequest!)
        : ref.read(cartProvider);
    if (cart.isEmpty || cart.merchantId == null || cart.branchId == null)
      return;
    final items = _relevantItems(cart);
    if (items.isEmpty) return;
    final orderDaysCount = _orderDaysCount(items);

    final merchant = ref.read(merchantDetailProvider(cart.merchantId!)).valueOrNull;
    if (merchant?.isBuyOnBehalf == true && !_autoFindDriver && _selectedDriver == null) {
      setState(() => _driverPickError = 'Chọn 1 tài xế trước khi đặt hàng, hoặc chọn "Để hệ thống tự tìm"');
      return;
    }
    setState(() => _driverPickError = null);

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
            .createOrder(
              _orderBody(cart, entry.value, address, entry.key, deliveryFee, orderDaysCount),
            );
        lastOrderId = order.id;
        created++;
      }
      // "Mua ngay" chưa từng thêm món vào giỏ hàng thật — không có gì để xoá, giữ nguyên
      // giỏ hàng hiện có của khách.
      if (widget.buyNowRequest == null) {
        await ref
            .read(cartProvider.notifier)
            .removeItems(items.map((i) => i.lineId).toList());
      }
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
    final cart = widget.buyNowRequest != null
        ? _buyNowCart(widget.buyNowRequest!)
        : ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesProvider);
    final publicVouchersAsync = cart.merchantId == null
        ? null
        : ref.watch(publicVouchersProvider(cart.merchantId!));
    final maxVouchers = ref.watch(voucherMaxCountProvider).valueOrNull ?? 1;
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

    // Đặt trước dùng preorderSchedule để nhóm theo từng ngày; giá sỉ không có lịch tuần
    // nhưng vẫn cần nhóm (đúng 1 nhóm gồm mọi món) để tính đúng điều kiện min_order_quantity
    // theo tổng số lượng cả đơn — _groupByOccurrence tự trả về 1 nhóm duy nhất khi
    // preorderSchedule null.
    final scheduledOrders =
        (widget.preorderSchedule != null || widget.initialScheduledFor != null)
        ? _groupByOccurrence(items)
        : null;
    final itemsSubtotal = scheduledOrders != null
        ? _tierAwareSubtotal(scheduledOrders, _orderDaysCount(items))
        : items.fold<int>(0, (sum, i) => sum + i.lineTotal);

    // Chốt địa chỉ mặc định sớm (trước khi cần tới trong shippingFee/nút Đặt hàng) —
    // giữ đúng logic cũ (ưu tiên is_default, không thì lấy địa chỉ đầu tiên).
    final addresses = addressesAsync.valueOrNull ?? const <Address>[];
    if (_selectedAddressId == null && addresses.isNotEmpty) {
      final defaultAddr = addresses.where((a) => a.isDefault).toList();
      _selectedAddressId = defaultAddr.isNotEmpty
          ? defaultAddr.first.id
          : addresses.first.id;
    }
    final shippingFee =
        _estimatedShippingFee(cart, addresses, itemsSubtotal) ?? 0;

    // Phí mua hộ chỉ để KHÁCH XEM TRƯỚC — server tự tính lại số thật lúc tạo đơn (không
    // gửi lên như delivery_fee), nên sai khác nhỏ do làm tròn không ảnh hưởng số tiền thu
    // thật. Xem BuyOnBehalfFeeEstimate.compute — mirror đúng cách chọn bậc phía server.
    final merchant = cart.merchantId == null
        ? null
        : ref.watch(merchantDetailProvider(cart.merchantId!)).valueOrNull;
    final branch = cart.branchId == null
        ? null
        : ref.watch(branchDetailProvider(cart.branchId!)).valueOrNull;
    final feeTiers = (merchant != null && merchant.isBuyOnBehalf)
        ? ref.watch(merchantFeeTiersProvider(cart.merchantId!)).valueOrNull ?? const []
        : const <MerchantFeeTier>[];
    final buyOnBehalfEstimate = merchant == null
        ? const BuyOnBehalfFeeEstimate(tier: null, fee: 0)
        : BuyOnBehalfFeeEstimate.compute(
            merchant: merchant,
            tiers: feeTiers,
            quantityTotal: items.fold<int>(0, (sum, i) => sum + i.quantity),
            subtotal: itemsSubtotal,
          );
    final buyOnBehalfFee = buyOnBehalfEstimate.fee;

    final total = itemsSubtotal + shippingFee + buyOnBehalfFee - _voucherDiscount;

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
            data: (addresses) => Column(
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
                if (_selectedAddressId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Phí giao hàng tới địa chỉ này: '
                            '${shippingFee == 0 ? 'Miễn phí' : formatVnd(shippingFee)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mã giảm giá', style: theme.textTheme.titleSmall),
              if (maxVouchers > 1)
                Text(
                  '${_appliedVouchers.length}/$maxVouchers mã',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ..._appliedVouchers.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_offer,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mã "${v.code}" — giảm ${formatVnd(v.discount)}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _removeVoucher(v.code),
                      child: const Text('Bỏ'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_appliedVouchers.length < maxVouchers)
            OutlinedButton.icon(
              onPressed: (_voucherChecking || cart.merchantId == null)
                  ? null
                  : () => _pickVoucher(
                      publicVouchersAsync?.valueOrNull ?? [],
                      cart.merchantId!,
                      itemsSubtotal,
                      shippingFee,
                    ),
              icon: _voucherChecking
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_offer_outlined),
              label: Text(
                _appliedVouchers.isEmpty
                    ? 'Chọn hoặc nhập mã giảm giá'
                    : 'Thêm mã khác',
              ),
            ),
          if (_voucherError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _voucherError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const Divider(height: 32),
          if (merchant != null && merchant.isBuyOnBehalf) ...[
            BuyOnBehalfFeeNotice(merchant: merchant),
            const SizedBox(height: 12),
            Text('Cách tìm tài xế', style: theme.textTheme.titleSmall),
            RadioGroup<bool>(
              groupValue: _autoFindDriver,
              onChanged: (v) => setState(() {
                _autoFindDriver = v ?? true;
                if (_autoFindDriver) _driverPickError = null;
              }),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text('Để hệ thống tự tìm tài xế gần nhất'),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('Tự chọn tài xế ưng ý'),
                  ),
                ],
              ),
            ),
            if (!_autoFindDriver) ...[
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: _selectedDriver?.avatarUrl != null ? NetworkImage(_selectedDriver!.avatarUrl!) : null,
                    child: _selectedDriver?.avatarUrl == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(_selectedDriver?.fullName ?? 'Chưa chọn tài xế'),
                  subtitle: _selectedDriver != null
                      ? Text(
                          '★ ${_selectedDriver!.ratingAvg.toStringAsFixed(1)}'
                          '${_selectedDriver!.vehicleType != null ? ' · ${_selectedDriver!.vehicleType}' : ''}',
                        )
                      : const Text('Bấm để xem tài xế đang online gần cửa hàng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: (branch?.latitude == null || branch?.longitude == null)
                      ? null
                      : () async {
                          final picked = await showDriverPickerDialog(context, lat: branch!.latitude!, lng: branch.longitude!);
                          if (picked != null) setState(() => _selectedDriver = picked);
                        },
                ),
              ),
              if (_driverPickError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_driverPickError!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
            const Divider(height: 32),
          ],
          Text('Phương thức thanh toán', style: theme.textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: _effectivePaymentMethod(cart),
            onChanged: (merchant?.isBuyOnBehalf ?? false)
                ? (_) {}
                : (v) => setState(() => _paymentMethod = v ?? _paymentMethod),
            child: Column(
              children: [
                if (!(merchant?.isBuyOnBehalf ?? false))
                  const RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'cod',
                    title: Text('Thanh toán khi nhận hàng (COD)'),
                  ),
                const RadioListTile<String>(
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
          Text('Sản phẩm', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...items.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.productName),
                        Text(
                          '${i.variantName} · ${i.quantity} x ${formatVnd(i.unitPrice + i.toppingsTotal)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatVnd(i.lineTotal),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [const Text('Tạm tính'), Text(formatVnd(itemsSubtotal))],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Phí giao hàng'),
                Text(shippingFee == 0 ? 'Miễn phí' : formatVnd(shippingFee)),
              ],
            ),
          ),
          if (buyOnBehalfFee > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Phí mua hộ'),
                  Text(formatVnd(buyOnBehalfFee)),
                ],
              ),
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
                    final address = addresses
                        .where((a) => a.id == _selectedAddressId)
                        .toList();
                    if (address.isEmpty) return;
                    _placeOrder(address.first, shippingFee);
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

/// 1 voucher đã được kiểm tra hợp lệ và thêm vào đơn — [discount] là số tiền server
/// (POST /vouchers/validate) đã tính, không phải ước tính riêng ở client.
class _AppliedVoucher {
  final String code;
  final int discount;
  const _AppliedVoucher({required this.code, required this.discount});
}
