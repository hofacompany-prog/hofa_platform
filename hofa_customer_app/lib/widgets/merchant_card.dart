import 'package:flutter/material.dart';
import '../models/merchant.dart';
import 'buy_on_behalf_badge.dart';
import 'network_image_box.dart';

class MerchantCard extends StatelessWidget {
  final Merchant merchant;
  final VoidCallback onTap;

  const MerchantCard({super.key, required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClosed = !merchant.hasOpenBranch;
    return Opacity(
      opacity: isClosed ? 0.55 : 1,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Stack(
                  children: [
                    NetworkImageBox(
                      url: merchant.logoUrl,
                      width: 64,
                      height: 64,
                      fallbackIcon: Icons.storefront_outlined,
                    ),
                    if (isClosed)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              merchant.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isClosed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Đóng cửa',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (merchant.isStandard)
                            Icon(
                              Icons.verified,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                      if (merchant.isBuyOnBehalf) ...[
                        const SizedBox(height: 4),
                        const BuyOnBehalfBadge(),
                      ],
                      const SizedBox(height: 4),
                      if (merchant.description != null &&
                          merchant.description!.isNotEmpty)
                        Text(
                          merchant.description!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${merchant.ratingAvg.toStringAsFixed(1)} (${merchant.ratingCount})',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${merchant.avgPrepMinutes} phút',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
