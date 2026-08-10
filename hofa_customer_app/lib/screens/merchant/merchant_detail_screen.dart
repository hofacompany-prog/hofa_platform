import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../providers/app_providers.dart';
import '../../widgets/buy_on_behalf_badge.dart';
import '../../widgets/buy_on_behalf_fee_notice.dart';
import '../../widgets/full_screen_gallery_viewer.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/product_card.dart';

/// Dải ảnh nhỏ cạnh logo cửa hàng — tối đa 3 ảnh, ảnh cuối đè số "+N" nếu còn ảnh chưa hiện.
/// Bấm ảnh nào mở xem full màn hình bắt đầu đúng ảnh đó, vuốt được sang các ảnh còn lại.
class _MerchantPhotoStrip extends StatelessWidget {
  final List<String> photoUrls;
  const _MerchantPhotoStrip({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    final shown = photoUrls.take(1).toList();
    final hasMore = photoUrls.length > shown.length;
    return SizedBox(
      width: 72,
      height: 72,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < shown.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => FullScreenGalleryViewer.open(
                context,
                images: photoUrls,
                initialIndex: i,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  shown[i],
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // Còn ảnh chưa hiện — bấm mới xem hết, không hiện đè lên ảnh như trước.
          if (hasMore)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => FullScreenGalleryViewer.open(
                context,
                images: photoUrls,
                initialIndex: 0,
              ),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Icon(
                    Icons.more_horiz,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MerchantDetailScreen extends ConsumerStatefulWidget {
  final String merchantId;
  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantDetailScreen> createState() => _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends ConsumerState<MerchantDetailScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(merchantProductsPagedProvider(widget.merchantId).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchantId = widget.merchantId;
    final merchantAsync = ref.watch(merchantDetailProvider(merchantId));
    final productsState = ref.watch(merchantProductsPagedProvider(merchantId));
    final categoriesAsync = ref.watch(merchantCategoriesProvider(merchantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: merchantAsync.maybeWhen(data: (m) => Text(m.name), orElse: () => const Text('Cửa hàng')),
      ),
      body: merchantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (merchant) {
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NetworkImageBox(url: merchant.logoUrl, width: 72, height: 72, fallbackIcon: Icons.storefront_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(merchant.name, style: theme.textTheme.titleLarge)),
                            if (merchant.isStandard) Icon(Icons.verified, color: theme.colorScheme.primary),
                          ],
                        ),
                        if (merchant.isBuyOnBehalf) ...[
                          const SizedBox(height: 4),
                          const BuyOnBehalfBadge(),
                        ],
                        if (merchant.description != null && merchant.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(merchant.description!, style: theme.textTheme.bodyMedium),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Text('${merchant.ratingAvg.toStringAsFixed(1)} (${merchant.ratingCount} đánh giá)'),
                            const SizedBox(width: 16),
                            Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text('${merchant.avgPrepMinutes} phút'),
                          ],
                        ),
                        if (merchant.minOrderAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Đơn tối thiểu: ${merchant.minOrderAmount}đ', style: theme.textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                  if (merchant.photoUrls.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _MerchantPhotoStrip(photoUrls: merchant.photoUrls),
                  ],
                ],
              ),
              if (merchant.isBuyOnBehalf) BuyOnBehalfFeeNotice(merchant: merchant),
              if (!merchant.hasOpenBranch) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, size: 18, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cửa hàng đang tạm đóng cửa — bạn vẫn xem được sản phẩm nhưng chưa đặt hàng được lúc này.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text('Sản phẩm', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (productsState.isInitialLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (productsState.error != null && productsState.items.isEmpty)
                Center(child: Text('Lỗi: ${productsState.error}'))
              else ...[
                _ProductGrid(
                  products: productsState.items,
                  categories: categoriesAsync.maybeWhen(
                    data: (v) => v,
                    orElse: () => const [],
                  ),
                ),
                if (productsState.hasMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  final List<MerchantCategory> categories;
  const _ProductGrid({required this.products, this.categories = const []});

  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _filter = 'all'; // all | instant | scheduled
  // null = "Tất cả danh mục" — chọn 1 danh mục cụ thể thì bỏ hẳn cách chia theo từng nhóm,
  // chỉ hiện đúng sản phẩm của danh mục đó (khách chủ động lọc rồi, không cần thấy nhóm khác).
  String? _categoryFilter;

  Widget _grid(List<Product> items) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        itemBuilder: (context, i) {
          final p = items[i];
          return ProductCard(product: p, onTap: () => GoRouter.of(context).push('/products/${p.id}'));
        },
      );

  @override
  Widget build(BuildContext context) {
    final hasInstant = widget.products.any((p) => p.salesModel == 'instant');
    final hasWholesale = widget.products.any((p) => p.salesModel == 'scheduled');
    final showFilter = hasInstant && hasWholesale;

    final visible = _filter == 'all' ? widget.products : widget.products.where((p) => p.salesModel == _filter).toList();

    if (widget.products.isEmpty) {
      return const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('Cửa hàng chưa có sản phẩm')));
    }

    final categoryDropdown = widget.categories.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String?>(
              initialValue: _categoryFilter,
              decoration: const InputDecoration(
                labelText: 'Danh mục cửa hàng',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả danh mục')),
                ...widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _categoryFilter = v),
            ),
          );

    final filterChips = showFilter
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Tất cả'), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
                ChoiceChip(
                    label: const Text('Giao ngay'), selected: _filter == 'instant', onSelected: (_) => setState(() => _filter = 'instant')),
                ChoiceChip(
                    label: const Text('Bán sỉ / Đặt trước'),
                    selected: _filter == 'scheduled',
                    onSelected: (_) => setState(() => _filter = 'scheduled')),
              ],
            ),
          )
        : const SizedBox.shrink();

    // Cửa hàng chưa tự cài đặt danh mục nào, hoặc khách đã lọc còn đúng 1 danh mục cụ thể —
    // cả 2 trường hợp đều không cần chia nhóm nữa, hiện phẳng 1 lưới duy nhất.
    if (widget.categories.isEmpty || _categoryFilter != null) {
      final filtered = _categoryFilter == null
          ? visible
          : visible.where((p) => p.merchantCategoryId == _categoryFilter).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          categoryDropdown,
          filterChips,
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 12),
              child: Center(child: Text('Không có sản phẩm nào trong danh mục này')),
            )
          else
            _grid(filtered),
        ],
      );
    }

    final byCategory = <String, List<Product>>{};
    for (final p in visible) {
      final key = p.merchantCategoryId ?? '_none';
      (byCategory[key] ??= []).add(p);
    }
    final sections = <MapEntry<String, List<Product>>>[
      for (final c in widget.categories)
        if (byCategory[c.id] != null) MapEntry(c.name, byCategory[c.id]!),
      if (byCategory['_none'] != null) MapEntry('Khác', byCategory['_none']!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        categoryDropdown,
        filterChips,
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(s.key, style: Theme.of(context).textTheme.titleSmall),
          ),
          _grid(s.value),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
