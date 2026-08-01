import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../providers/app_providers.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/product_card.dart';

class MerchantDetailScreen extends ConsumerWidget {
  final String merchantId;
  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(merchantDetailProvider(merchantId));
    final productsAsync = ref.watch(merchantProductsProvider(merchantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: merchantAsync.maybeWhen(data: (m) => Text(m.name), orElse: () => const Text('Cửa hàng')),
      ),
      body: merchantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (merchant) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NetworkImageBox(url: merchant.logoUrl, width: 72, height: 72, fallbackIcon: Icons.storefront_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(merchant.name, style: theme.textTheme.titleLarge)),
                            if (merchant.isStandard) Icon(Icons.verified, color: theme.colorScheme.primary),
                          ],
                        ),
                        if (merchant.description != null && merchant.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(merchant.description!, style: theme.textTheme.bodyMedium),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Text('${merchant.ratingAvg.toStringAsFixed(1)} (${merchant.ratingCount} đánh giá)'),
                            const SizedBox(width: 16),
                            Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text('${merchant.avgPrepMinutes} phút'),
                          ],
                        ),
                        if (merchant.minOrderAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Đơn tối thiểu: ${merchant.minOrderAmount}đ', style: theme.textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text('Sản phẩm', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              productsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Center(child: Text('Lỗi: $e')),
                data: (products) => _ProductGrid(products: products),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  const _ProductGrid({required this.products});

  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _filter = 'all'; // all | instant | scheduled

  @override
  Widget build(BuildContext context) {
    final hasInstant = widget.products.any((p) => p.salesModel == 'instant');
    final hasWholesale = widget.products.any((p) => p.salesModel == 'scheduled');
    final showFilter = hasInstant && hasWholesale;

    final visible = _filter == 'all' ? widget.products : widget.products.where((p) => p.salesModel == _filter).toList();

    if (widget.products.isEmpty) {
      return const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('Cửa hàng chưa có sản phẩm')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showFilter)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Tất cả'), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
                ChoiceChip(
                    label: const Text('Giao ngay'), selected: _filter == 'instant', onSelected: (_) => setState(() => _filter = 'instant')),
                ChoiceChip(
                    label: const Text('Bán sỉ / Đặt trước'),
                    selected: _filter == 'scheduled',
                    onSelected: (_) => setState(() => _filter = 'scheduled')),
              ],
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemBuilder: (context, i) {
            final p = visible[i];
            return ProductCard(product: p, onTap: () => GoRouter.of(context).push('/products/${p.id}'));
          },
        ),
      ],
    );
  }
}
