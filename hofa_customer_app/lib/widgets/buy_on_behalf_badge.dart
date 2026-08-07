import 'package:flutter/material.dart';

/// Nhãn "Mua hộ" gắn lên cửa hàng merchantType == 'buy_on_behalf' — cửa hàng dạng này cộng
/// thêm phí mua hộ vào tổng thanh toán (xem merchant_fee_tiers, hiển thị chi tiết ở
/// buy_on_behalf_fee_notice.dart).
class BuyOnBehalfBadge extends StatelessWidget {
  final double iconSize;
  final TextStyle? textStyle;
  const BuyOnBehalfBadge({super.key, this.iconSize = 12, this.textStyle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
        ],
      ),
    );
  }
}
