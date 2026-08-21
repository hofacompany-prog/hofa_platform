import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/address.dart';
import '../../models/product.dart';
import '../../providers/app_providers.dart';
import '../../widgets/address_map_flow.dart';
import '../../widgets/favorites_icon.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/merchant_card.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/product_card.dart';

/// Địa chỉ hiện lên thanh "Giao ngay" ở đầu trang chủ — ưu tiên địa chỉ mặc định, không có thì
/// lấy địa chỉ đầu tiên (cùng quy tắc chọn địa chỉ tự động lúc vào checkout).
Address? _pickDisplayAddress(List<Address>? addresses) {
  if (addresses == null || addresses.isEmpty) return null;
  final defaults = addresses.where((a) => a.isDefault);
  return defaults.isNotEmpty ? defaults.first : addresses.first;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  List<Product> _suggestions = [];
  bool _suggesting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Chỉ tải thêm cửa hàng khi đang ở chế độ duyệt mặc định (không tìm kiếm) — tránh gọi
  /// thừa lúc khách đang cuộn xem kết quả tìm kiếm (danh sách khác hẳn, không phân trang).
  void _onScroll() {
    final isSearching = ref.read(productSearchProvider).isNotEmpty;
    if (isSearching) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(merchantsPagedProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _suggesting = true);
      final results = await ref
          .read(productRepoProvider)
          .products(q: q, limit: 6);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _suggesting = false;
      });
    });
  }

  void _runFullSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    setState(() => _suggestions = []);
    ref.read(productSearchProvider.notifier).state = q;
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _suggestions = []);
    ref.read(productSearchProvider.notifier).state = '';
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final merchantsState = ref.watch(merchantsPagedProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final homeSort = ref.watch(homeSortProvider);
    final ratingFilterSelected = ref.watch(ratingFilterSelectedProvider);
    final classificationsAsync = ref.watch(merchantClassificationsProvider);
    final selectedClassificationIds = ref.watch(
      selectedClassificationIdsProvider,
    );
    final hasCoords = ref.watch(customerCoordsProvider) != null;
    final searchQuery = ref.watch(productSearchProvider);
    final searchedProductsAsync = ref.watch(searchedProductsProvider);
    final searchedMerchantsAsync = ref.watch(searchedMerchantsProvider);
    final isSearching = searchQuery.isNotEmpty;
    final showSuggestions = _suggestions.isNotEmpty || _suggesting;

    final displayAddress = _pickDisplayAddress(
      ref.watch(addressesProvider).valueOrNull,
    );

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => addAddressViaMap(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Giao ngay',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ],
                ),
                Text(
                  displayAddress?.fullLine ?? 'Vị trí hiện tại',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        centerTitle: false,
        actions: const [FavoritesIcon(), NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(merchantsPagedProvider),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm sản phẩm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (isSearching || _searchCtrl.text.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
              onSubmitted: _runFullSearch,
            ),
            // Gợi ý nhỏ khi đang gõ — bấm 1 gợi ý hoặc nhấn Enter mới chạy tìm kiếm đầy
            // đủ (danh sách lớn) bên dưới, tránh gọi API nặng liên tục theo từng ký tự.
            if (showSuggestions)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _suggesting
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _suggestions
                            .map(
                              (p) => ListTile(
                                dense: true,
                                leading: NetworkImageBox(
                                  url: p.images.isNotEmpty
                                      ? p.images.first
                                      : null,
                                  width: 40,
                                  height: 40,
                                  borderRadius: BorderRadius.circular(8),
                                  fallbackIcon: Icons.shopping_bag_outlined,
                                ),
                                title: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: p.defaultVariant != null
                                    ? Text(formatVnd(p.defaultVariant!.price))
                                    : null,
                                onTap: () {
                                  _searchCtrl.text = p.name;
                                  _runFullSearch(p.name);
                                },
                              ),
                            )
                            .toList(),
                      ),
              ),
            const SizedBox(height: 20),
            if (showSuggestions)
              const SizedBox()
            else if (isSearching)
              Builder(
                builder: (context) {
                  final merchants = searchedMerchantsAsync.valueOrNull ?? [];
                  final productsLoading = searchedProductsAsync.isLoading;
                  final merchantsLoading = searchedMerchantsAsync.isLoading;
                  if (productsLoading && merchantsLoading) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return searchedProductsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('Lỗi: $e')),
                    ),
                    data: (products) {
                      if (products.isEmpty && merchants.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Không tìm thấy cửa hàng hay sản phẩm nào',
                            ),
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cửa hàng khớp tên tìm kiếm — hiện cả cửa hàng đang tạm đóng (khác
                          // danh sách duyệt mặc định phía dưới, MerchantCard tự xám nó lại).
                          if (merchants.isNotEmpty) ...[
                            Text(
                              'Cửa hàng',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ...merchants.map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: MerchantCard(
                                  merchant: m,
                                  onTap: () =>
                                      context.push('/merchants/${m.id}'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (products.isNotEmpty) ...[
                            Text(
                              'Sản phẩm',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: products.length,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 220,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 0.62,
                                  ),
                              itemBuilder: (context, i) {
                                final p = products[i];
                                return ProductCard(
                                  product: p,
                                  onTap: () =>
                                      context.push('/products/${p.id}'),
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              )
            else ...[
              categoriesAsync.when(
                loading: () => const SizedBox(),
                error: (_, _) => const SizedBox(),
                data: (categories) => CategoryGrid(
                  categories: categories
                      .where((c) => c.parentId == null)
                      .toList(),
                  onTapCategory: (c) =>
                      context.push('/categories/${c.id}', extra: c.name),
                  onTapViewAll: () => context.push('/categories'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip(
                      label: 'Gần tôi',
                      selected: homeSort == 'distance',
                      onTap: hasCoords
                          ? () => ref.read(homeSortProvider.notifier).state =
                                homeSort == 'distance' ? null : 'distance'
                          : null,
                    ),
                    const SizedBox(width: 8),
                    // Đánh giá cao xuống thấp — mặc định server đã sắp xếp sẵn theo rating_avg
                    // DESC (xem GET /merchants). Tick độc lập với "Gần tôi" (không phải radio) —
                    // chỉ đổi trạng thái hiện của chính nó.
                    _filterChip(
                      label: 'Đánh giá',
                      selected: ratingFilterSelected,
                      onTap: () =>
                          ref
                                  .read(ratingFilterSelectedProvider.notifier)
                                  .state =
                              !ratingFilterSelected,
                    ),
                    // Viên nang lọc theo phân loại cửa hàng (Nhà hàng/Cà phê/...) — chọn được
                    // nhiều cùng lúc, chung 1 hàng cuộn ngang với "Gần tôi"/"Đánh giá" ở trên.
                    ...classificationsAsync.maybeWhen(
                      data: (items) => items
                          .expand(
                            (c) => [
                              const SizedBox(width: 8),
                              _filterChip(
                                label: c.name,
                                selected: selectedClassificationIds.contains(
                                  c.id,
                                ),
                                onTap: () {
                                  final next = Set<String>.from(
                                    selectedClassificationIds,
                                  );
                                  selectedClassificationIds.contains(c.id)
                                      ? next.remove(c.id)
                                      : next.add(c.id);
                                  ref
                                          .read(
                                            selectedClassificationIdsProvider
                                                .notifier,
                                          )
                                          .state =
                                      next;
                                },
                              ),
                            ],
                          )
                          .toList(),
                      orElse: () => const <Widget>[],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (merchantsState.isInitialLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (merchantsState.error != null &&
                  merchantsState.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(child: Text('Lỗi: ${merchantsState.error}')),
                )
              else
                Builder(
                  builder: (context) {
                    // Cửa hàng tạm đóng (không còn chi nhánh nào mở) chỉ hiện lại khi khách chủ
                    // động tìm kiếm (xem MerchantCard vẫn xám nó ở đó) — ở đây là danh sách
                    // duyệt mặc định của trang chủ nên ẩn hẳn, đỡ dẫn khách bấm vào rồi thất vọng.
                    final merchants = merchantsState.items
                        .where((m) => m.hasOpenBranch)
                        .toList();
                    if (merchants.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text('Không tìm thấy cửa hàng nào'),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        ...merchants.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MerchantCard(
                              merchant: m,
                              onTap: () => context.push('/merchants/${m.id}'),
                            ),
                          ),
                        ),
                        if (merchantsState.hasMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
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
