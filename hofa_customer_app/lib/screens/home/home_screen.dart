import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/merchant_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantsAsync = ref.watch(merchantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HOFA'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(merchantsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm cửa hàng...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                isDense: true,
              ),
              onSubmitted: (v) => ref.read(merchantSearchProvider.notifier).state = v.trim(),
            ),
            const SizedBox(height: 16),
            merchantsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Lỗi: $e'))),
              data: (merchants) {
                if (merchants.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('Không tìm thấy cửa hàng nào')),
                  );
                }
                return Column(
                  children: merchants
                      .map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MerchantCard(merchant: m, onTap: () => context.push('/merchants/${m.id}')),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
