import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/require_login.dart';
import '../../models/cart_item.dart';
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
  /// chưa đủ dữ liệu để ước tính (chưa có địa chỉ, thiếu toạ độ chi nhánh...).
  int? _estimatedShippingFee(WidgetRef ref, CartState cart) {
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
    return settings.estimate(distanceKm, orderAmount: cart.subtotal);
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
    final shippingFee = isInstantCart ? _estimatedShippingFee(ref, cart) : null;

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
                      Text(
                        cart.merchantName ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                                      formatVnd(
                                        item.unitPrice + item.toppingsTotal,
                                      ),
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
                                    formatVnd(item.lineTotal),
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
                                formatVnd(cart.subtotal),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (shippingFee != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Phí giao hàng (ước tính): '
                                  '${shippingFee == 0 ? 'Miễn phí' : formatVnd(shippingFee)}',
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
