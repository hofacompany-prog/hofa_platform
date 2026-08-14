import 'package:flutter/material.dart';
import '../core/geo.dart';
import '../models/merchant.dart';
import 'buy_on_behalf_badge.dart';
import 'merchant_favorite_button.dart';
import 'network_image_box.dart';

class MerchantCard extends StatelessWidget {
  final Merchant merchant;
  final VoidCallback onTap;

  const MerchantCard({super.key, required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClosed = !merchant.hasOpenBranch;
    // Đỏ = chủ cửa hàng đang tạm nghỉ (chủ động tắt); xám = chỉ đơn thuần ngoài giờ hoạt động
    // đã cấu hình, không phải tạm nghỉ — xem hofa-db/78_branch_operating_hours_gate.sql.
    final closedColor = merchant.displayStatus == 'closed_hours'
        ? Colors.grey
        : theme.colorScheme.error;
    final closedLabel = merchant.displayStatus == 'closed_hours'
        ? 'Đóng cửa'
        : 'Tạm nghỉ';
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
                                color: closedColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                closedLabel,
                                style: const TextStyle(
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
                          if (merchant.distanceKm != null) ...[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: merchant.beyondOwnRadius
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              formatDistanceKm(merchant.distanceKm!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: merchant.beyondOwnRadius
                                    ? theme.colorScheme.secondary
                                    : null,
                                fontWeight: merchant.beyondOwnRadius
                                    ? FontWeight.w600
                                    : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                MerchantFavoriteButton(merchantId: merchant.id),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
