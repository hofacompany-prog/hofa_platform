import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Xoá giỏ hàng',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(cartProvider.notifier).clear(),
            ),
        ],
      ),
      body: cart.isEmpty
          ? const Center(child: Text('Giỏ hàng đang trống'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(cart.merchantName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                              NetworkImageBox(url: item.productImage, width: 56, height: 56),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    Text(item.variantName, style: theme.textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text(formatVnd(item.unitPrice), style: TextStyle(color: theme.colorScheme.primary)),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                                        onPressed: () => ref
                                            .read(cartProvider.notifier)
                                            .updateQuantity(item.variantId, item.quantity - 1),
                                      ),
                                      Text('${item.quantity}'),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.add_circle_outline, size: 20),
                                        onPressed: () => ref
                                            .read(cartProvider.notifier)
                                            .updateQuantity(item.variantId, item.quantity + 1),
                                      ),
                                    ],
                                  ),
                                  Text(formatVnd(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withValues(alpha: 0.08), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tạm tính', style: theme.textTheme.bodySmall),
                              Text(formatVnd(cart.subtotal), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () => context.push('/checkout'),
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
