import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/earnings.dart';
import '../../repositories/driver_repository.dart';

final _earningsProvider = FutureProvider.autoDispose<Earnings>((ref) => DriverRepository().earnings());

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(_earningsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Thu nhập')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_earningsProvider),
        child: earningsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (earnings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Số dư ví', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(formatVnd(earnings.walletBalance),
                          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        earnings.walletBalance < 0
                            ? 'Số âm là tiền COD bạn đang giữ hộ, cần nộp lại cho HOFA'
                            : 'Có thể rút về tài khoản ngân hàng',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(label: 'Hôm nay', value: formatVnd(earnings.todayTotal)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(label: 'Tổng chuyến', value: '${earnings.totalDeliveries}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(label: 'Đánh giá', value: '${earnings.ratingAvg}★ (${earnings.ratingCount} lượt)'),
              const SizedBox(height: 24),
              Text('Chuyến gần đây', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (earnings.recentDeliveries.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Chưa có chuyến nào'))
              else
                ...earnings.recentDeliveries.map((d) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(formatVnd(d.driverFee)),
                        subtitle: Text(d.deliveredAt != null ? formatDateTime(d.deliveredAt!) : '—'),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
