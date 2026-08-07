import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/format.dart';
import '../models/merchant.dart';
import '../models/merchant_fee_tier.dart';
import '../providers/app_providers.dart';
import 'buy_on_behalf_badge.dart';

/// Thông báo + bảng bậc phí mua hộ — đặt ở màn chi tiết cửa hàng và chi tiết sản phẩm để
/// khách biết trước sẽ bị cộng thêm phí này trước khi vào thanh toán (nơi phí thật sự được
/// tính vào tổng). Không hiển thị gì nếu cửa hàng không phải merchantType == 'buy_on_behalf'.
class BuyOnBehalfFeeNotice extends ConsumerWidget {
  final Merchant merchant;
  const BuyOnBehalfFeeNotice({super.key, required this.merchant});

  String _thresholdLabel(String basis, int min, int? max) {
    if (basis == 'quantity') {
      return max == null ? 'Từ $min sản phẩm trở lên' : 'Từ $min đến $max sản phẩm';
    }
    return max == null
        ? 'Từ ${formatVnd(min)} trở lên'
        : 'Từ ${formatVnd(min)} đến ${formatVnd(max)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!merchant.isBuyOnBehalf) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final basis = merchant.buyOnBehalfFeeBasis;
    final tiersAsync = ref.watch(merchantFeeTiersProvider(merchant.id));

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuyOnBehalfBadge(iconSize: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cửa hàng mua hộ — có phụ phí tính vào tổng thanh toán',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          tiersAsync.when(
            loading: () => const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (tiers) {
              if (basis == null || tiers.isEmpty) {
                return Text(
                  'Cửa hàng chưa cấu hình phí mua hộ.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tiers
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _thresholdLabel(basis, t.minThreshold, t.maxThreshold),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              t.isFixed ? formatVnd(t.feeFixedAmount ?? 0) : '${t.feePercent}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Bậc phí đang áp dụng cho 1 giỏ hàng thực tế + số tiền ước tính — dùng ở màn thanh toán.
/// [quantityTotal]/[subtotal] là số liệu của RIÊNG cửa hàng mua hộ này trong giỏ.
class BuyOnBehalfFeeEstimate {
  final MerchantFeeTier? tier;
  final int fee;
  const BuyOnBehalfFeeEstimate({required this.tier, required this.fee});

  static BuyOnBehalfFeeEstimate compute({
    required Merchant merchant,
    required List<MerchantFeeTier> tiers,
    required int quantityTotal,
    required int subtotal,
  }) {
    if (!merchant.isBuyOnBehalf || merchant.buyOnBehalfFeeBasis == null) {
      return const BuyOnBehalfFeeEstimate(tier: null, fee: 0);
    }
    final basisValue = merchant.buyOnBehalfFeeBasis == 'value' ? subtotal : quantityTotal;
    final tier = matchBuyOnBehalfTier(tiers, basisValue);
    return BuyOnBehalfFeeEstimate(tier: tier, fee: estimateBuyOnBehalfFee(tier, subtotal));
  }
}
