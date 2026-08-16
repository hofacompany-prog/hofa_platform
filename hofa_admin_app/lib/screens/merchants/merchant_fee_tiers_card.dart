import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../models/merchant_fee_tier.dart';
import '../../providers/admin_providers.dart';
import '../../core/responsive.dart';
import '../../core/vnd_input_formatter.dart';

/// Cấu hình bậc phí mua hộ cho 1 cửa hàng merchant_type = 'buy_on_behalf' — admin tự thiết
/// lập ở đây (khác wholesale_tiers, do chủ cửa hàng tự cấu hình theo biến thể sản phẩm).
/// customer app đọc lại đúng các bậc này để hiển thị ở màn sản phẩm/thanh toán; server tự
/// tính phí thật khi tạo đơn (xem create_order trong hofa-db/28_merchant_buy_on_behalf.sql),
/// số hiển thị ở đây chỉ để admin xem trước — không phải nơi chốt giá.
class MerchantFeeTiersCard extends ConsumerStatefulWidget {
  final Merchant merchant;
  const MerchantFeeTiersCard({super.key, required this.merchant});

  @override
  ConsumerState<MerchantFeeTiersCard> createState() =>
      _MerchantFeeTiersCardState();
}

class _MerchantFeeTiersCardState extends ConsumerState<MerchantFeeTiersCard> {
  bool _savingBasis = false;
  bool _savingReset = false;

  String get _merchantId => widget.merchant.id;

  Future<void> _changeBasis(String basis) async {
    if (basis == widget.merchant.buyOnBehalfFeeBasis || _savingBasis) return;
    setState(() => _savingBasis = true);
    try {
      await ref.read(adminRepoProvider).updateMerchant(_merchantId, {
        'buy_on_behalf_fee_basis': basis,
      });
      ref.invalidate(merchantDetailProvider(_merchantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingBasis = false);
    }
  }

  Future<void> _openTierDialog({MerchantFeeTier? existing}) async {
    final basis = widget.merchant.buyOnBehalfFeeBasis;
    if (basis == null) return;
    final minCtrl = TextEditingController(
      text: basis == 'value'
          ? VndInputFormatter.display(existing?.minThreshold)
          : existing?.minThreshold.toString() ?? '',
    );
    final maxCtrl = TextEditingController(
      text: basis == 'value'
          ? VndInputFormatter.display(existing?.maxThreshold)
          : existing?.maxThreshold?.toString() ?? '',
    );
    final fixedCtrl = TextEditingController(
      text: VndInputFormatter.display(existing?.feeFixedAmount),
    );
    final percentCtrl = TextEditingController(
      text: existing?.feePercent?.toString() ?? '',
    );
    var feeType = existing?.feeType ?? 'fixed';
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(existing == null ? 'Thêm bậc phí' : 'Sửa bậc phí'),
          content: SizedBox(
            width: dialogWidth(context, 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    basis == 'quantity'
                        ? 'Ngưỡng tính theo số lượng sản phẩm trong đơn'
                        : 'Ngưỡng tính theo giá trị đơn hàng (VNĐ)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            if (basis == 'value')
                              VndInputFormatter()
                            else
                              FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: basis == 'quantity'
                                ? 'Từ (SL)'
                                : 'Từ (VNĐ)',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            if (basis == 'value')
                              VndInputFormatter()
                            else
                              FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: basis == 'quantity'
                                ? 'Đến (SL)'
                                : 'Đến (VNĐ)',
                            hintText: 'Không giới hạn',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cách tính phí',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Cố định (VNĐ)'),
                        selected: feeType == 'fixed',
                        onSelected: (_) => setInner(() => feeType = 'fixed'),
                      ),
                      ChoiceChip(
                        label: const Text('Phần trăm (%)'),
                        selected: feeType == 'percent',
                        onSelected: (_) => setInner(() => feeType = 'percent'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (feeType == 'fixed')
                    TextField(
                      controller: fixedCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [VndInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Phí mua hộ (VNĐ)',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    TextField(
                      controller: percentCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phần trăm giá trị đơn (%)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () {
                final min = VndInputFormatter.parse(minCtrl.text);
                final max = VndInputFormatter.parse(maxCtrl.text);
                if (min == null || min < 0) {
                  setInner(() => errorText = 'Ngưỡng "Từ" không hợp lệ');
                  return;
                }
                if (max != null && max < min) {
                  setInner(() => errorText = 'Ngưỡng "Đến" phải ≥ "Từ"');
                  return;
                }
                if (feeType == 'fixed' &&
                    VndInputFormatter.parse(fixedCtrl.text) == null) {
                  setInner(() => errorText = 'Nhập số tiền phí hợp lệ');
                  return;
                }
                if (feeType == 'percent') {
                  final p = num.tryParse(percentCtrl.text.trim());
                  if (p == null || p < 0 || p > 100) {
                    setInner(() => errorText = 'Phần trăm phải từ 0 đến 100');
                    return;
                  }
                }
                Navigator.pop(context, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;

    final data = {
      'min_threshold': VndInputFormatter.parse(minCtrl.text),
      'max_threshold': VndInputFormatter.parse(maxCtrl.text),
      'fee_type': feeType,
      'fee_fixed_amount': feeType == 'fixed'
          ? VndInputFormatter.parse(fixedCtrl.text)
          : null,
      'fee_percent': feeType == 'percent'
          ? num.parse(percentCtrl.text.trim())
          : null,
    };

    try {
      if (existing == null) {
        await ref.read(adminRepoProvider).createFeeTier(_merchantId, data);
      } else {
        await ref.read(adminRepoProvider).updateFeeTier(existing.id, data);
      }
      ref.invalidate(merchantFeeTiersProvider(_merchantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteTier(MerchantFeeTier tier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá bậc phí?'),
        content: const Text('Bậc phí này sẽ bị xoá khỏi cửa hàng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepoProvider).deleteFeeTier(tier.id);
      ref.invalidate(merchantFeeTiersProvider(_merchantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  /// Xoá hết bậc phí riêng đang có của cửa hàng, đổi lại đúng cách tính ngưỡng bậc + toàn bộ
  /// bậc phí mặc định toàn sàn (xem Tài chính > Phí mua hộ) — dùng khi muốn quay lại đúng mức
  /// phí chung, không giữ lại phần đã tự chỉnh riêng.
  Future<void> _resetToPlatformDefault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đưa về phí mua hộ mặc định toàn sàn?'),
        content: const Text(
          'Toàn bộ bậc phí riêng đang có của cửa hàng này sẽ bị XOÁ và thay bằng đúng cách '
          'tính ngưỡng + bậc phí mặc định toàn sàn (cấu hình ở Tài chính > Phí mua hộ). '
          'Không hoàn tác được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đưa về mặc định'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _savingReset = true);
    try {
      await ref
          .read(adminRepoProvider)
          .resetMerchantFeeTiersToPlatformDefault(_merchantId);
      ref.invalidate(merchantFeeTiersProvider(_merchantId));
      ref.invalidate(merchantDetailProvider(_merchantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã đưa về phí mua hộ mặc định toàn sàn'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingReset = false);
    }
  }

  String _thresholdLabel(String basis, int min, int? max) {
    if (basis == 'quantity') {
      return max == null
          ? 'Từ $min sản phẩm trở lên'
          : 'Từ $min đến $max sản phẩm';
    }
    return max == null
        ? 'Từ ${formatVnd(min)} trở lên'
        : 'Từ ${formatVnd(min)} đến ${formatVnd(max)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final basis = widget.merchant.buyOnBehalfFeeBasis;
    final tiersAsync = ref.watch(merchantFeeTiersProvider(_merchantId));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text('Phí mua hộ', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cộng thêm vào tổng thanh toán khi khách đặt hàng ở cửa hàng này — hiện ở '
              'màn sản phẩm và thanh toán của app khách.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text('Cách tính ngưỡng bậc', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: buyOnBehalfFeeBasisLabels.entries
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: basis == e.key,
                      onSelected: _savingBasis
                          ? null
                          : (_) => _changeBasis(e.key),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (basis == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Chọn cách tính ngưỡng bậc ở trên trước khi thêm bậc phí.',
                      ),
                    ),
                  ],
                ),
              )
            else
              tiersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Lỗi: $e'),
                data: (tiers) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tiers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Chưa có bậc phí nào — khách sẽ không bị tính phí mua hộ cho '
                          'đến khi thêm ít nhất 1 bậc.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    else
                      ...tiers.map(
                        (t) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _thresholdLabel(
                                    basis,
                                    t.minThreshold,
                                    t.maxThreshold,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: theme.colorScheme.secondary
                                    .withValues(alpha: 0.12),
                                label: Text(
                                  t.isFixed
                                      ? formatVnd(t.feeFixedAmount ?? 0)
                                      : '${t.feePercent}%',
                                  style: TextStyle(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _openTierDialog(existing: t),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () => _deleteTier(t),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openTierDialog(),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Thêm bậc'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _savingReset
                              ? null
                              : _resetToPlatformDefault,
                          icon: _savingReset
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.restore),
                          label: const Text('Phí mua hộ mặc định'),
                        ),
                      ],
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
