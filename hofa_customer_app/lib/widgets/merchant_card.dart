import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/format.dart';
import '../core/geo.dart';
import '../models/merchant.dart';
import '../models/voucher.dart';
import '../providers/app_providers.dart';
import 'buy_on_behalf_badge.dart';
import 'merchant_favorite_button.dart';
import 'network_image_box.dart';

class MerchantCard extends ConsumerWidget {
  final Merchant merchant;
  final VoidCallback onTap;
  // Ẩn được ở nơi không cần (vd trang chủ) — mặc định vẫn hiện để không đổi hành vi những chỗ
  // khác đang dùng (màn Yêu thích...).
  final bool showFavoriteButton;

  const MerchantCard({
    super.key,
    required this.merchant,
    required this.onTap,
    this.showFavoriteButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      width: 84,
                      height: 84,
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
                      // Nhãn "Mua hộ" neo TRÊN CÙNG bên phải, cùng hàng với tên — tên chỉ 1
                      // dòng, dài quá thì "…", không đẩy mất nhãn ra ngoài vì nhãn nằm NGOÀI
                      // Expanded (không co dãn theo tên).
                      SizedBox(
                        height: 22,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                merchant.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
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
                            if (merchant.isBuyOnBehalf) ...[
                              const SizedBox(width: 4),
                              const BuyOnBehalfBadge(),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Thay mô tả bằng dải mã giảm giá cửa hàng đang có, cuộn ngang nếu nhiều —
                      // vẫn chừa cố định 1 chiều cao dù cửa hàng không có voucher nào, giữ các
                      // thẻ cao bằng nhau (như mô tả trước đây).
                      SizedBox(
                        height: 28,
                        child: _VoucherChipsRow(merchantId: merchant.id),
                      ),
                      const SizedBox(height: 4),
                      // Wrap thay vì Row — tên cửa hàng dài hoặc màn hình hẹp có thể khiến
                      // tổng bề rộng rating + thời gian + khoảng cách vượt quá chỗ trống, Wrap
                      // tự xuống dòng thay vì báo lỗi tràn (RenderFlex overflow).
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
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
                            ],
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                          if (merchant.distanceKm != null) ...[
                            const SizedBox(width: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showFavoriteButton)
                  MerchantFavoriteButton(merchantId: merchant.id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dải chip mã giảm giá công khai của 1 cửa hàng, cuộn ngang nếu nhiều — dùng lại đúng nguồn dữ
/// liệu với voucher_picker_dialog.dart (publicVouchersProvider) nên không cần gọi API riêng.
class _VoucherChipsRow extends ConsumerWidget {
  final String merchantId;

  const _VoucherChipsRow({required this.merchantId});

  IconData _iconFor(String discountType) {
    switch (discountType) {
      case 'percent':
        return Icons.percent;
      case 'free_shipping':
        return Icons.local_shipping_outlined;
      default:
        return Icons.sell_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vouchers =
        ref.watch(publicVouchersProvider(merchantId)).valueOrNull
            ?.where((v) => !v.isExpired)
            .toList() ??
        const <Voucher>[];
    if (vouchers.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      itemCount: vouchers.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final voucher = vouchers[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(voucher.discountType),
                size: 12,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                voucher.discountLabel(formatVnd),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
