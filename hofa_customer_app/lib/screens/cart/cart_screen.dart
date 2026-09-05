import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/require_login.dart';
import '../../models/cart_item.dart';
import '../../models/merchant_fee_tier.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/topping_picker_dialog.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  /// Ước tính phí ship theo khoảng cách từ chi nhánh tới địa chỉ MẶC ĐỊNH của khách — chỉ
  /// để xem trước ở giỏ hàng, chưa chắc đúng số tiền sẽ tính vào đơn thật vì khách có thể
  /// đổi sang địa chỉ khác ở màn thanh toán (xem checkout_screen.dart, nơi phí ship được
  /// tính lại theo đúng địa chỉ đã chọn và thật sự cộng vào Tổng cộng). Trả về null nếu
  /// chưa đủ dữ liệu để ước tính (chưa có địa chỉ, thiếu toạ độ chi nhánh...). [subtotal]
  /// truyền vào ngoài (thay vì tự đọc cart.subtotal) để dùng đúng giá ĐÃ CỘNG % mua hộ khi có.
  int? _estimatedShippingFee(WidgetRef ref, CartState cart, int subtotal) {
    final branchId = cart.branchId;
    if (branchId == null) return null;
    final settings = ref.watch(shippingFeeSettingsProvider).valueOrNull;
    if (settings == null) return null;
    final branch = ref.watch(branchDetailProvider(branchId)).valueOrNull;
    if (branch == null || branch.latitude == null || branch.longitude == null) {
      return null;
    }
    final addresses = ref.watch(addressesProvider).valueOrNull ?? const [];
    if (addresses.isEmpty) return null;
    final address = addresses.firstWhere(
      (a) => a.isDefault,
      orElse: () => addresses.first,
    );
    if (address.latitude == null || address.longitude == null) return null;
    final distanceKm = haversineKm(
      branch.latitude!,
      branch.longitude!,
      address.latitude!,
      address.longitude!,
    );
    return settings.estimate(distanceKm, orderAmount: subtotal);
  }

  Future<void> _editToppings(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) async {
    final groups = await ref
        .read(productRepoProvider)
        .toppingGroups(item.productId);
    if (groups.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sản phẩm này không có topping')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final result = await showToppingPickerDialog(
      context,
      groups: groups,
      initiallySelected: item.toppings,
      initialNote: item.note,
      showQuantity: false,
    );
    if (result != null) {
      await ref
          .read(cartProvider.notifier)
          .updateToppings(item.lineId, result.toppings, note: result.note);
    }
  }

  /// Bấm nút trừ mà số lượng về 0 nghĩa là xoá hẳn món khỏi giỏ — hỏi xác nhận trước khi
  /// xoá thật, tránh xoá nhầm khi lỡ tay bấm liên tục.
  Future<void> _decreaseQuantity(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) async {
    final newQuantity = item.quantity - 1;
    if (newQuantity <= 0) {
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
      if (confirm != true) return;
    }
    await ref
        .read(cartProvider.notifier)
        .updateQuantity(item.lineId, newQuantity);
  }

  /// Xoá cả giỏ là hành động không hoàn tác được và mất hết lựa chọn đã thêm — luôn hỏi
  /// xác nhận trước, tránh xoá nhầm khi lỡ tay bấm icon trên AppBar.
  Future<void> _clearCart(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá giỏ hàng?'),
        content: const Text('Toàn bộ sản phẩm trong giỏ sẽ bị xoá.'),
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
    if (confirm != true) return;
    await ref.read(cartProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    // Giỏ chỉ chứa 1 hình thức bán tại 1 thời điểm (xem CartNotifier.belongsToCurrentCart)
    // — món đặt trước/bán sỉ hiển thị ở tab "Đặt trước", không lặp lại ở đây.
    final isInstantCart = !cart.isEmpty && cart.salesModel == 'instant';

    // Cửa hàng mua hộ: giá hiển thị ở giỏ hàng cũng cộng % theo đúng bậc của CẢ GIỎ (tổng giá
    // trị/số lượng các món cùng cửa hàng này) — khớp với màn thanh toán, không chỉ tính ở đó
    // nữa. Xem hofa-db/108_buy_on_behalf_price_fold_and_small_order_fee.sql.
    final merchant = cart.merchantId == null
        ? null
        : ref.watch(merchantDetailProvider(cart.merchantId!)).valueOrNull;
    final feeTiers = (merchant != null && merchant.isBuyOnBehalf)
        ? ref.watch(merchantFeeTiersProvider(cart.merchantId!)).valueOrNull ??
              const <MerchantFeeTier>[]
        : const <MerchantFeeTier>[];
    final buyOnBehalfTier = (merchant != null && merchant.isBuyOnBehalf)
        ? matchBuyOnBehalfTier(
            feeTiers,
            merchant.buyOnBehalfFeeBasis == 'value'
                ? cart.items.fold<int>(
                    0,
                    (sum, i) =>
                        sum + (i.basePrice + i.toppingsTotal) * i.quantity,
                  )
                : cart.items.fold<int>(0, (sum, i) => sum + i.quantity),
          )
        : null;
    int displayUnitPrice(CartItem i) => (merchant != null && merchant.isBuyOnBehalf)
        ? markedUpUnitPrice(i.basePrice + i.toppingsTotal, buyOnBehalfTier)
        : i.unitPrice + i.toppingsTotal;
    int displayLineTotal(CartItem i) => displayUnitPrice(i) * i.quantity;
    final displaySubtotal = (merchant != null && merchant.isBuyOnBehalf)
        ? cart.items.fold<int>(0, (sum, i) => sum + displayLineTotal(i))
        : cart.subtotal;

    final shippingFee = isInstantCart
        ? _estimatedShippingFee(ref, cart, displaySubtotal)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        actions: [
          if (isInstantCart)
            IconButton(
              tooltip: 'Xoá giỏ hàng',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _clearCart(context, ref),
            ),
        ],
      ),
      body: !isInstantCart
          ? const Center(child: Text('Giỏ hàng đang trống'))
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
                      Expanded(
                        child: Text(
                          cart.merchantName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = cart.items[i];
                      return Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              NetworkImageBox(
                                url: item.productImage,
                                width: 56,
                                height: 56,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                              color:
                                                  theme.colorScheme.secondary,
                                            ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatVnd(displayUnitPrice(item)),
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () =>
                                          _editToppings(context, ref, item),
                                      child: const Text('Sửa topping'),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20,
                                        ),
                                        onPressed: () => _decreaseQuantity(
                                          context,
                                          ref,
                                          item,
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
                                  Text(
                                    formatVnd(displayLineTotal(item)),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tạm tính',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                formatVnd(displaySubtotal),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (shippingFee != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Phí giao hàng (ước tính): '
                                  '${shippingFee == 0 ? 'Miễn phí' : formatVnd(shippingFee)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () async {
                            if (!await requireLogin(context)) return;
                            if (context.mounted) context.push('/checkout');
                          },
                          child: const Text('Đặt hàng'),
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
