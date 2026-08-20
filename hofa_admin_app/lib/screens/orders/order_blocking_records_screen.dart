import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../providers/admin_providers.dart';

/// Tên bảng (khớp BLOCKING_TABLES ở server/src/routes/order-blocking-records.js) -> nhãn
/// tiếng Việt hiện cho admin.
const _tableLabels = {
  'driver_wallet_transactions': 'Giao dịch ví tài xế',
  'payments': 'Giao dịch thanh toán',
  'merchant_wallet_transactions': 'Giao dịch ví cửa hàng',
  'driver_cod_settlement_items': 'Mục quyết toán COD tài xế',
};

/// Xem + xoá 4 loại dữ liệu có thể chặn "Xoá đơn hàng" (khoá ngoại order_id không CASCADE) —
/// mở từ order_detail_screen.dart khi admin dính lỗi khoá ngoại lúc xoá đơn. Xoá xong quay lại
/// bấm "Xoá đơn hàng" lại là được, màn này KHÔNG tự xoá đơn.
class OrderBlockingRecordsScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderBlockingRecordsScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderBlockingRecordsScreen> createState() =>
      _OrderBlockingRecordsScreenState();
}

class _OrderBlockingRecordsScreenState
    extends ConsumerState<OrderBlockingRecordsScreen> {
  bool _busy = false;

  Future<void> _delete({List<String>? tables}) async {
    final label = tables == null
        ? 'TOÀN BỘ dữ liệu bên dưới'
        : tables.map((t) => _tableLabels[t] ?? t).join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá dữ liệu?'),
        content: Text(
          'Sẽ xoá vĩnh viễn $label của đơn này. Đây là dữ liệu SỔ SÁCH (ví/thanh toán) — chỉ '
          'xoá khi chắc chắn đây là đơn rác/lỗi, xoá xong không khôi phục lại được và có thể '
          'làm lệch số dư/tổng hợp đã tính trước đó.',
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

    setState(() => _busy = true);
    try {
      final deleted = await ref
          .read(adminRepoProvider)
          .deleteOrderBlockingRecords(widget.orderId, tables: tables);
      ref.invalidate(orderBlockingRecordsProvider(widget.orderId));
      final total = deleted.values.fold<int>(
        0,
        (sum, v) => sum + (v as int),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá $total dòng')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(orderBlockingRecordsProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/orders/${widget.orderId}'),
        ),
        title: const Text('Dữ liệu chặn xoá đơn'),
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          final tables = data['tables'] as Map<String, dynamic>;
          final totalRows = tables.values.fold<int>(
            0,
            (sum, rows) => sum + (rows as List).length,
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.4,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_outlined,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Đơn ${data['order_code']} — 4 bảng dưới đây khoá xoá đơn '
                                '(order_id không tự dọn theo). Xoá xong bấm lại "Xoá đơn hàng" '
                                'ở màn chi tiết đơn.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (totalRows > 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: _busy ? null : () => _delete(),
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('Xoá tất cả'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (totalRows == 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text('Không còn dữ liệu nào chặn xoá đơn này'),
                        ),
                      )
                    else
                      ..._tableLabels.entries.map((entry) {
                        final rows = (tables[entry.key] as List)
                            .cast<Map<String, dynamic>>();
                        if (rows.isEmpty) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${entry.value} (${rows.length})',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                  _delete(tables: [entry.key]),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        label: const Text('Xoá nhóm này'),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  ...rows.map(
                                    (row) => _RowTile(row: row),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
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

/// Hiện gọn các field có ý nghĩa của 1 dòng (bỏ id/order_id vì không cần đối chiếu) — mỗi bảng
/// có cột khác nhau nên không dựng model riêng, in trực tiếp key: value.
class _RowTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _RowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = row['created_at'] != null
        ? DateTime.tryParse(row['created_at'].toString())
        : null;
    final fields = row.entries
        .where(
          (e) =>
              !['id', 'order_id', 'created_at'].contains(e.key) &&
              e.value != null,
        )
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (createdAt != null)
            Text(formatDateTime(createdAt), style: theme.textTheme.bodySmall),
          Text(fields, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
