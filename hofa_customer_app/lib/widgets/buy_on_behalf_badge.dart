import 'package:flutter/material.dart';

/// Nhãn "Mua hộ" gắn lên cửa hàng merchantType == 'buy_on_behalf' — cửa hàng dạng này cộng
/// thêm phí mua hộ vào tổng thanh toán (xem merchant_fee_tiers). Chi tiết bảng phí
/// (buy_on_behalf_fee_notice.dart) CHỈ hiện khi bấm vào đúng nhãn này (xem
/// merchant_detail_screen.dart — nơi duy nhất truyền [onTap]) — mọi nơi khác dùng nhãn này chỉ
/// để hiển thị (vd merchant_card.dart), không truyền onTap nên không bấm được.
class BuyOnBehalfBadge extends StatelessWidget {
  final double iconSize;
  final TextStyle? textStyle;
  final VoidCallback? onTap;
  const BuyOnBehalfBadge({super.key, this.iconSize = 12, this.textStyle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined, size: iconSize, color: theme.colorScheme.secondary),
          const SizedBox(width: 4),
          Text(
            'Mua hộ',
            style: (textStyle ?? theme.textTheme.labelSmall)?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.info_outline, size: iconSize, color: theme.colorScheme.secondary),
          ],
        ],
      ),
    );
    if (onTap == null) return badge;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: badge,
    );
  }
}
