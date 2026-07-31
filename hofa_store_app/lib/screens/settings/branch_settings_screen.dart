import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/branch.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';

final _branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return MerchantRepository().branches(merchant.id);
});

class BranchSettingsScreen extends ConsumerWidget {
  const BranchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(myMerchantProvider);
    final branchesAsync = ref.watch(_branchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                merchantAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (m) => m == null
                      ? const SizedBox()
                      : Card(
                          child: ListTile(
                            title: Text(m.name),
                            subtitle: Text('Trạng thái: ${m.status} · Hoa hồng: ${m.commissionRate}%'),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Text('Chi nhánh', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                branchesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Lỗi: $e'),
                  data: (branches) => Column(
                    children: branches
                        .map((b) => Card(
                              child: SwitchListTile(
                                title: Text(b.name),
                                subtitle: Text('${b.line1}, ${b.province}'),
                                value: b.isOpen,
                                onChanged: (val) async {
                                  try {
                                    await MerchantRepository().toggleBranchOpen(b.id, val);
                                    ref.invalidate(_branchesProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                                    }
                                  }
                                },
                                secondary: Icon(
                                  b.isOpen ? Icons.storefront : Icons.storefront_outlined,
                                  color: b.isOpen ? Colors.green : Colors.grey,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tắt công tắc khi hết hàng hoặc nghỉ đột xuất — cửa hàng sẽ tạm ngừng nhận đơn mới.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
