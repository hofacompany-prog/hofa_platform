import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/earnings.dart';
import '../../repositories/driver_repository.dart';
import '../../widgets/image_upload_field.dart';

final _codPendingOrdersProvider =
    FutureProvider.autoDispose<List<CodPendingOrder>>(
      (ref) => DriverRepository().codPendingOrders(),
    );

/// Nộp COD theo lô — tick chọn đúng các đơn muốn nộp, không bắt buộc nộp hết 1 lần (xem
/// hofa-db/62_driver_wallet_ledger.sql, RPC submit_driver_cod_settlement).
class CodSettlementScreen extends ConsumerStatefulWidget {
  const CodSettlementScreen({super.key});

  @override
  ConsumerState<CodSettlementScreen> createState() =>
      _CodSettlementScreenState();
}

class _CodSettlementScreenState extends ConsumerState<CodSettlementScreen> {
  final Set<String> _selected = {};
  String? _proofImageUrl;
  bool _submitting = false;

  Future<void> _submit(List<CodPendingOrder> orders) async {
    if (_selected.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await DriverRepository().submitCodSettlement(
        orderIds: _selected.toList(),
        proofImageUrl: _proofImageUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã gửi yêu cầu nộp COD — HOFA sẽ xác nhận sớm.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(_codPendingOrdersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nộp COD')),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('Không có đơn COD nào cần nộp'));
          }
          final total = orders
              .where((o) => _selected.contains(o.orderId))
              .fold<int>(0, (sum, o) => sum + o.totalAmount);
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: orders.length,
                  itemBuilder: (context, i) {
                    final o = orders[i];
                    final checked = _selected.contains(o.orderId);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(o.orderId);
                        } else {
                          _selected.remove(o.orderId);
                        }
                      }),
                      title: Text(o.orderCode),
                      subtitle: Text(
                        o.deliveredAt != null
                            ? formatDateTime(o.deliveredAt!)
                            : '—',
                      ),
                      secondary: Text(
                        formatVnd(o.totalAmount),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ImageUploadField(
                        label: 'Ảnh chuyển khoản (không bắt buộc)',
                        folder: 'deliveries',
                        onChanged: (url) =>
                            setState(() => _proofImageUrl = url),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tổng chọn'),
                          Text(
                            formatVnd(total),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: (_selected.isEmpty || _submitting)
                            ? null
                            : () => _submit(orders),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Xác nhận nộp'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
