import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../providers/admin_providers.dart';

const _deliveryStatusLabels = {
  'pending': 'Chờ nhận',
  'assigned': 'Đã gán',
  'accepted': 'Đã nhận',
  'arrived_store': 'Tới cửa hàng',
  'picked_up': 'Đã lấy hàng',
  'delivering': 'Đang giao',
};

/// Xem trước dữ liệu chặn "Xoá tài xế" (xem DELETE /admin/drivers/:id) — chuyến giao chưa hoàn
/// tất + số dư ví (COD giữ hộ/thu nhập chưa rút). Mở từ driver_detail_screen.dart. Không tự
/// xoá/đổi gì — chuyến giao xử lý ở màn "Chuyến giao hàng", ví quyết toán ở tab "Ví tài xế".
class DriverBlockingRecordsScreen extends ConsumerWidget {
  final String driverId;
  const DriverBlockingRecordsScreen({super.key, required this.driverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(driverBlockingRecordsProvider(driverId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/drivers/$driverId'),
        ),
        title: const Text('Dữ liệu chặn xoá tài xế'),
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          final activeDeliveries = (data['active_deliveries'] as List)
              .cast<Map<String, dynamic>>();
          final codBalance = (data['cod_balance'] as num).toInt();
          final earningBalance = (data['earning_balance'] as num).toInt();
          final nothingBlocks =
              activeDeliveries.isEmpty && codBalance == 0 && earningBalance == 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 0,
                      color: nothingBlocks
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.4,
                            )
                          : theme.colorScheme.errorContainer.withValues(
                              alpha: 0.4,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              nothingBlocks
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_outlined,
                              color: nothingBlocks
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                nothingBlocks
                                    ? 'Không có gì chặn xoá, có thể xoá tài xế này.'
                                    : 'Đang bị chặn xoá bởi dữ liệu bên dưới.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (activeDeliveries.isNotEmpty) ...[
                      Text(
                        'Chuyến giao chưa hoàn tất (${activeDeliveries.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Column(
                          children: activeDeliveries
                              .map(
                                (dl) => ListTile(
                                  leading: const Icon(
                                    Icons.local_shipping_outlined,
                                  ),
                                  title: Text(
                                    dl['order_code'] as String? ??
                                        dl['order_id'] as String,
                                  ),
                                  subtitle: Text(
                                    _deliveryStatusLabels[dl['status']] ??
                                        dl['status'] as String,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () =>
                                      context.push('/deliveries/${dl['id']}'),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          'Gán tài xế khác hoặc huỷ chuyến ở màn "Chuyến giao hàng" trước.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (codBalance != 0 || earningBalance != 0) ...[
                      Text('Số dư ví', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (codBalance != 0)
                                Text('Ví trên (COD giữ hộ): ${formatVnd(codBalance)}'),
                              if (earningBalance != 0)
                                Text('Ví thu nhập: ${formatVnd(earningBalance)}'),
                              const SizedBox(height: 4),
                              const Text(
                                'Quyết toán/cho rút hết ở tab "Ví tài xế" trước khi xoá.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
