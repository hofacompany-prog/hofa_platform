import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/merchant_card.dart';
import '../../widgets/product_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(productSearchProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final merchantsAsync = ref.watch(merchantsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final searchQuery = ref.watch(productSearchProvider);
    final searchedProductsAsync = ref.watch(searchedProductsProvider);
    final isSearching = searchQuery.isNotEmpty;

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
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm sản phẩm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: isSearching ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch) : null,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                isDense: true,
              ),
              onSubmitted: (v) => ref.read(productSearchProvider.notifier).state = v.trim(),
            ),
            const SizedBox(height: 20),
            if (isSearching)
              searchedProductsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Lỗi: $e'))),
                data: (products) {
                  if (products.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('Không tìm thấy sản phẩm nào')),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    itemBuilder: (context, i) {
                      final p = products[i];
                      return ProductCard(product: p, onTap: () => context.push('/products/${p.id}'));
                    },
                  );
                },
              )
            else ...[
              categoriesAsync.when(
                loading: () => const SizedBox(),
                error: (_, _) => const SizedBox(),
                data: (categories) => CategoryGrid(
                  categories: categories.where((c) => c.parentId == null).toList(),
                  onTapCategory: (c) => context.push('/categories/${c.id}', extra: c.name),
                  onTapViewAll: () => context.push('/categories'),
                ),
              ),
              const SizedBox(height: 20),
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
          ],
        ),
      ),
    );
  }
}
