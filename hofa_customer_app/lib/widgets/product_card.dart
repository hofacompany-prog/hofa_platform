import 'package:flutter/material.dart';
import '../core/format.dart';
import '../models/product.dart';
import 'network_image_box.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = product.defaultVariant;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  NetworkImageBox(
                    url: product.images.isNotEmpty ? product.images.first : null,
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
                        label: const Text('Bán sỉ', style: TextStyle(fontSize: 11)),
                        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.9),
                        labelStyle: const TextStyle(color: Colors.white),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
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
                  Text(product.name,
                      style: const TextStyle(fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  if (variant != null)
                    Row(
                      children: [
                        Text(formatVnd(variant.price),
                            style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                        if (variant.comparePrice != null && variant.comparePrice! > variant.price) ...[
                          const SizedBox(width: 6),
                          Text(
                            formatVnd(variant.comparePrice!),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(decoration: TextDecoration.lineThrough, color: theme.colorScheme.outline),
                          ),
                        ],
                      ],
                    ),
                  if (product.soldCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Đã bán ${product.soldCount}', style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
