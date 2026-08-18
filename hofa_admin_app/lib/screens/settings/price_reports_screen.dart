import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/price_report.dart';
import '../../providers/admin_providers.dart';

/// Danh sách báo cáo giá sai (từ khách/tài xế) đang chờ duyệt — duyệt thì áp thẳng giá vào biến
/// thể sản phẩm (PATCH /variants/:id qua PATCH /admin/price-reports/:id), xem
/// hofa-db/89_product_price_reports.sql.
class PriceReportsScreen extends ConsumerStatefulWidget {
  const PriceReportsScreen({super.key});

  @override
  ConsumerState<PriceReportsScreen> createState() =>
      _PriceReportsScreenState();
}

class _PriceReportsScreenState extends ConsumerState<PriceReportsScreen> {
  final Map<String, TextEditingController> _priceCtrls = {};
  final Set<String> _busyIds = {};

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(PriceReport r) => _priceCtrls.putIfAbsent(
    r.id,
    () => TextEditingController(text: '${r.reportedPrice}'),
  );

  Future<void> _approve(PriceReport r) async {
    final finalPrice = int.tryParse(_ctrlFor(r).text.trim());
    if (finalPrice == null || finalPrice < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giá áp dụng không hợp lệ')));
      return;
    }
    setState(() => _busyIds.add(r.id));
    try {
      await ref
          .read(adminRepoProvider)
          .approvePriceReport(r.id, finalPrice: finalPrice);
      ref.invalidate(pendingPriceReportsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã duyệt — cập nhật giá ${formatVnd(finalPrice)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  Future<void> _reject(PriceReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Từ chối báo cáo này?'),
        content: Text(
          '${r.productName}${r.variantName.isNotEmpty ? ' - ${r.variantName}' : ''} — giá sẽ giữ nguyên ${formatVnd(r.currentPrice)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyIds.add(r.id));
    try {
      await ref.read(adminRepoProvider).rejectPriceReport(r.id);
      ref.invalidate(pendingPriceReportsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportsAsync = ref.watch(pendingPriceReportsProvider);

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(child: Text('Không có báo cáo giá sai nào đang chờ'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (context, i) {
            final r = reports[i];
            final busy = _busyIds.contains(r.id);
            return Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          r.reporterRole == 'driver'
                              ? Icons.two_wheeler_outlined
                              : Icons.person_outline,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${r.reporterRole == 'driver' ? 'Tài xế' : 'Khách hàng'} '
                            '${r.reporterName}${r.reporterPhone != null ? ' — ${r.reporterPhone}' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        Text(
                          formatDateTime(r.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${r.productName}${r.variantName.isNotEmpty ? ' - ${r.variantName}' : ''}',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      r.merchantName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PriceBox(
                            label: 'Đang hiển thị',
                            value: formatVnd(r.currentPrice),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PriceBox(
                            label: 'Khách/tài xế báo',
                            value: formatVnd(r.reportedPrice),
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ctrlFor(r),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá áp dụng nếu duyệt',
                        border: OutlineInputBorder(),
                        suffixText: 'đ',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy ? null : () => _reject(r),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            child: const Text('Từ chối'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : () => _approve(r),
                            child: busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Duyệt'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PriceBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _PriceBox({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
