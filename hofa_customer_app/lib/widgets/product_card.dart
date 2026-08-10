import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/format.dart';
import '../core/geo.dart';
import '../models/product.dart';
import 'network_image_box.dart';
import 'quick_add_to_cart.dart';

class ProductCard extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback onTap;
  // Màn chi tiết cửa hàng đã hiện khoảng cách ở đầu trang rồi — tắt ở lưới sản phẩm trong đó
  // để khỏi lặp lại, các nơi khác (tìm kiếm, danh mục) vẫn hiện bình thường.
  final bool showDistance;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showDistance = true,
  });

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  bool _adding = false;

  Future<void> _quickAdd() async {
    setState(() => _adding = true);
    try {
      await quickAddToCart(context, ref, widget.product);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final variant = product.defaultVariant;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      NetworkImageBox(
                        url: product.images.isNotEmpty
                            ? product.images.first
                            : null,
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                        fallbackIcon: Icons.shopping_bag_outlined,
                      ),
                      if (product.isWholesale)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Chip(
                            label: const Text(
                              'Bán sỉ',
                              style: TextStyle(fontSize: 11),
                            ),
                            backgroundColor: theme.colorScheme.secondary
                                .withValues(alpha: 0.9),
                            labelStyle: const TextStyle(color: Colors.white),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      if (product.ratingCount > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  product.ratingAvg.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (variant != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatVnd(variant.price),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (variant.comparePrice != null &&
                                variant.comparePrice! > variant.price)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  formatVnd(variant.comparePrice!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (product.soldCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Đã bán ${product.soldCount}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (widget.showDistance && product.distanceKm != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 12,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                formatDistanceKm(product.distanceKm!),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (variant != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _adding ? null : _quickAdd,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: _adding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.add,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
