import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/merchant_fee_tier.dart';
import '../../models/platform_fee_settings.dart';
import '../../providers/admin_providers.dart';

/// Phí mua hộ MẶC ĐỊNH TOÀN SÀN — admin cấu hình 1 lần ở đây, tự copy sang bậc phí riêng
/// (merchant_fee_tiers, xem MerchantFeeTiersCard) cho MỖI cửa hàng merchant_type=
/// 'buy_on_behalf' MỚI TẠO (qua web admin hoặc công cụ GAS). Sửa/xoá bậc ở đây KHÔNG ảnh
/// hưởng ngược lại cửa hàng đã tạo trước đó — admin vẫn chỉnh riêng từng cửa hàng như cũ.
class PlatformFeeScreen extends ConsumerStatefulWidget {
  const PlatformFeeScreen({super.key});

  @override
  ConsumerState<PlatformFeeScreen> createState() => _PlatformFeeScreenState();
}

class _PlatformFeeScreenState extends ConsumerState<PlatformFeeScreen> {
  bool _savingBasis = false;

  Future<void> _changeBasis(String basis, String? current) async {
    if (basis == current || _savingBasis) return;
    setState(() => _savingBasis = true);
    try {
      await ref.read(adminRepoProvider).updatePlatformFeeBasis(basis);
      ref.invalidate(platformFeeSettingsProvider);
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

  Future<void> _openTierDialog(
    String basis, {
    PlatformFeeTier? existing,
  }) async {
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
        await ref.read(adminRepoProvider).createPlatformFeeTier(data);
      } else {
        await ref
            .read(adminRepoProvider)
            .updatePlatformFeeTier(existing.id, data);
      }
      ref.invalidate(platformFeeSettingsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteTier(PlatformFeeTier tier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá bậc phí?'),
        content: const Text(
          'Bậc phí mặc định toàn sàn này sẽ bị xoá — không ảnh hưởng bậc phí đã copy riêng '
          'cho các cửa hàng đã tạo trước đó.',
        ),
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
      await ref.read(adminRepoProvider).deletePlatformFeeTier(tier.id);
      ref.invalidate(platformFeeSettingsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
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
    final dataAsync = ref.watch(platformFeeSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Phí mua hộ')),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          final basis = data.settings.feeBasis;
          final tiers = data.tiers;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Áp dụng làm phí mua hộ MẶC ĐỊNH cho mọi cửa hàng "Mua hộ" mới tạo — '
                      'copy nguyên xi vào cửa hàng lúc tạo, sau đó admin vẫn chỉnh riêng cho '
                      'từng cửa hàng ở màn chi tiết cửa hàng như bình thường. Sửa ở đây '
                      'KHÔNG ảnh hưởng cửa hàng đã tạo trước đó.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cách tính ngưỡng bậc',
                              style: theme.textTheme.labelLarge,
                            ),
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
                                          : (_) => _changeBasis(e.key, basis),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 16),
                            if (tiers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  'Chưa có bậc phí mặc định nào — cửa hàng "Mua hộ" mới tạo '
                                  'sẽ chưa có phí mua hộ cho đến khi thêm ít nhất 1 bậc.',
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
                                        backgroundColor: theme
                                            .colorScheme
                                            .secondary
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
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () =>
                                            _openTierDialog(basis, existing: t),
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
                            OutlinedButton.icon(
                              onPressed: () => _openTierDialog(basis),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Thêm bậc'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
