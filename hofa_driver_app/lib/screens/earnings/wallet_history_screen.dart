import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/earnings.dart';
import '../../repositories/driver_repository.dart';

final _walletTransactionsProvider =
    FutureProvider.autoDispose<List<WalletTransaction>>(
      (ref) => DriverRepository().walletTransactions(),
    );

/// Lịch sử ví — cả 2 ví gộp chung 1 danh sách, mỗi dòng ghi rõ ví/loại/số tiền để tài xế truy
/// vết được vì sao số dư đổi (xem hofa-db/62_driver_wallet_ledger.sql).
class WalletHistoryScreen extends ConsumerWidget {
  const WalletHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_walletTransactionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử ví')),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Chưa có giao dịch nào'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final tx = list[i];
              final positive = tx.amount > 0;
              return Card(
                child: ListTile(
                  leading: Icon(
                    tx.wallet == 'cod'
                        ? Icons.local_shipping_outlined
                        : Icons.account_balance_wallet_outlined,
                    color: tx.wallet == 'cod'
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.primary,
                  ),
                  title: Text(
                    walletEntryTypeLabels[tx.entryType] ?? tx.entryType,
                  ),
                  subtitle: Text(
                    '${tx.wallet == 'cod' ? 'Ví COD' : 'Ví thu nhập'} · ${formatDateTime(tx.createdAt)}'
                    '${tx.note != null && tx.note!.isNotEmpty ? '\n${tx.note}' : ''}',
                  ),
                  isThreeLine: tx.note != null && tx.note!.isNotEmpty,
                  trailing: Text(
                    '${positive ? '+' : ''}${formatVnd(tx.amount)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: positive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
