import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../models/topping.dart';
import '../../models/wholesale_tier.dart';
import '../../providers/app_providers.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/topping_picker_dialog.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  ProductVariant? _selectedVariant;
  int _quantity = 1;
  bool _adding = false;
  List<ProductTopping> _selectedToppings = [];
  String? _note;

  void _ensureVariantSelected(Product product) {
    _selectedVariant ??= product.defaultVariant;
  }

  int _unitPriceFor(ProductVariant variant, List<WholesaleTier> tiers) {
    if (tiers.isEmpty) return variant.price;
    WholesaleTier? matched;
    for (final t in tiers) {
      if (_quantity >= t.minQuantity &&
          (t.maxQuantity == null || _quantity <= t.maxQuantity!)) {
        matched = t;
        break;
      }
    }
    return matched?.unitPrice ?? variant.price;
  }

  /// Sản phẩm bán sỉ/đặt trước phải chọn rõ thêm vào tab nào — Giá sỉ và Đặt trước xử lý
  /// lịch giao khác nhau nên không thể gộp chung 1 dòng giỏ hàng.
  Future<String?> _pickOrderKind() => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Thêm vào'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'wholesale'),
          child: const Text('Giá sỉ'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'preorder'),
          child: const Text('Đặt trước'),
        ),
      ],
    ),
  );

  Future<void> _addToCart(
    Product product,
    ProductVariant variant,
    int unitPrice,
    List<ToppingGroup> toppingGroups,
  ) async {
    var toppings = _selectedToppings;
    var note = _note;
    if (toppingGroups.isNotEmpty) {
      final result = await showToppingPickerDialog(
        context,
        groups: toppingGroups,
        initiallySelected: _selectedToppings,
        initialNote: _note,
      );
      if (result == null) return; // huỷ popup thì không thêm vào giỏ
      if (!mounted) return;
      toppings = result.toppings;
      note = result.note;
      setState(() {
        _selectedToppings = result.toppings;
        _note = result.note;
      });
    }

    String? orderKind;
    if (product.isWholesale) {
      orderKind = await _pickOrderKind();
      if (orderKind == null) return;
      if (!mounted) return;
    }

    final cartNotifier = ref.read(cartProvider.notifier);
    final cartState = ref.read(cartProvider);

    if (!cartNotifier.belongsToCurrentCart(
      product.merchantId,
      product.salesModel,
    )) {
      final differentMerchant = cartState.merchantId != product.merchantId;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            differentMerchant
                ? 'Giỏ hàng có món của cửa hàng khác'
                : 'Giỏ hàng có món khác hình thức bán',
          ),
          content: Text(
            differentMerchant
                ? 'Giỏ hàng hiện đang có món từ "${cartState.merchantName}". Mỗi đơn chỉ đặt được 1 cửa hàng — xoá giỏ hiện tại để thêm món mới?'
                : 'Giỏ hàng hiện đang có món ${cartState.salesModel == 'scheduled' ? 'đặt trước/bán sỉ' : 'giao ngay'}, khác với sản phẩm này. Giao ngay và đặt trước/bán sỉ đặt riêng — xoá giỏ hiện tại để thêm món mới?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xoá giỏ cũ'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await cartNotifier.clear();
    }

    setState(() => _adding = true);
    try {
      final branches = await ref.read(
        merchantBranchesProvider(product.merchantId).future,
      );
      if (branches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cửa hàng chưa có chi nhánh nhận đơn'),
            ),
          );
        }
        return;
      }
      final branch = branches.firstWhere(
        (b) => b.isMain,
        orElse: () => branches.first,
      );
      final merchant = await ref.read(
        merchantDetailProvider(product.merchantId).future,
      );

      await cartNotifier.addItem(
        merchantId: product.merchantId,
        merchantName: merchant.name,
        branchId: branch.id,
        salesModel: product.salesModel,
        item: CartItem(
          lineId: '${variant.id}_${DateTime.now().microsecondsSinceEpoch}',
          productId: product.id,
          productName: product.name,
          productImage: product.images.isNotEmpty ? product.images.first : null,
          variantId: variant.id,
          variantName: variant.name,
          unitPrice: unitPrice,
          basePrice: variant.price,
          quantity: _quantity,
          unit: product.unit,
          toppings: toppings,
          note: note,
          orderKind: orderKind,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderKind == 'wholesale'
                  ? 'Đã thêm vào Giá sỉ'
                  : orderKind == 'preorder'
                  ? 'Đã thêm vào Đặt trước'
                  : 'Đã thêm vào Giỏ hàng',
            ),
          ),
        );
        setState(() {
          _selectedToppings = [];
          _note = null;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailProvider(widget.productId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Sản phẩm'),
      ),
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (product) {
          _ensureVariantSelected(product);
          final variant = _selectedVariant ?? product.defaultVariant;
          final tiersAsync = (product.isWholesale && variant != null)
              ? ref.watch(wholesaleTiersProvider(variant.id))
              : null;
          final tiers = tiersAsync?.valueOrNull ?? [];
          // Giá xem trước ở đây chưa gắn với tab Giá sỉ/Đặt trước nào (khách chưa chọn) —
          // chỉ ước tính theo bậc giá sỉ (minDaysPerWeek = 0), không lẫn bậc đặt trước.
          final wholesaleOnlyTiers = tiers
              .where((t) => t.minDaysPerWeek == 0)
              .toList();
          final unitPrice = variant != null
              ? _unitPriceFor(variant, wholesaleOnlyTiers)
              : 0;
          final toppingGroups =
              ref.watch(toppingGroupsProvider(product.id)).valueOrNull ?? [];
          final toppingsTotal = _selectedToppings.fold(
            0,
            (sum, t) => sum + t.price,
          );

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AspectRatio(
                      aspectRatio: 1.3,
                      child: NetworkImageBox(
                        url: product.images.isNotEmpty
                            ? product.images.first
                            : null,
                        width: double.infinity,
                        height: double.infinity,
                        fallbackIcon: Icons.shopping_bag_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (product.isWholesale)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          label: const Text('Bán sỉ / Đặt trước'),
                          backgroundColor: theme.colorScheme.secondary
                              .withValues(alpha: 0.15),
                        ),
                      ),
                    Text(product.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          formatVnd(unitPrice),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' / ${product.unit}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    if (product.ratingCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${product.ratingAvg.toStringAsFixed(1)} (${product.ratingCount} đánh giá) · Đã bán ${product.soldCount}',
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (product.variants.length > 1) ...[
                      Text('Chọn loại', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: product.variants
                            .map(
                              (v) => ChoiceChip(
                                label: Text(v.name),
                                selected: _selectedVariant?.id == v.id,
                                onSelected: (_) => setState(() {
                                  _selectedVariant = v;
                                  _quantity = 1;
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (product.isWholesale && tiers.isNotEmpty) ...[
                      Text(
                        'Bậc giá theo số lượng',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Column(
                          children: tiers
                              .map(
                                (t) => ListTile(
                                  dense: true,
                                  title: Text(
                                    '${t.rangeLabel} ${product.unit}',
                                  ),
                                  subtitle: t.minDaysPerWeek > 0
                                      ? Text(
                                          'Đặt ≥${t.minDaysPerWeek} ngày/tuần: ${formatVnd(t.unitPriceDays ?? t.unitPrice)} · '
                                          'Đạt cả 2 điều kiện: ${formatVnd(t.unitPriceBoth ?? t.unitPrice)}',
                                        )
                                      : null,
                                  trailing: Text(
                                    formatVnd(t.unitPrice),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Số lượng', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 56,
                          child: Center(
                            child: Text(
                              '$_quantity',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          onPressed: () => setState(() => _quantity++),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    if (toppingGroups.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.tune,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Sản phẩm này có topping — chọn khi bấm "Thêm vào giỏ"',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedToppings.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _selectedToppings
                              .map(
                                (t) => Chip(
                                  label: Text(
                                    t.price > 0
                                        ? '${t.name} (+${formatVnd(t.price)})'
                                        : t.name,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                    if (product.description != null &&
                        product.description!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Mô tả', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(product.description!),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Đánh giá', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (context, ref, _) {
                        final reviewsAsync = ref.watch(
                          productReviewsProvider(product.id),
                        );
                        return reviewsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(),
                          ),
                          error: (e, _) => Text('Lỗi tải đánh giá: $e'),
                          data: (reviews) {
                            if (reviews.isEmpty)
                              return const Text('Chưa có đánh giá nào');
                            return Column(
                              children: reviews
                                  .map(
                                    (r) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: List.generate(
                                              5,
                                              (i) => Icon(
                                                i < r.rating
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 16,
                                                color: Colors.amber.shade700,
                                              ),
                                            ),
                                          ),
                                          if (r.comment != null &&
                                              r.comment!.isNotEmpty)
                                            Text(r.comment!),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: (variant == null || _adding)
                        ? null
                        : () => _addToCart(
                            product,
                            variant,
                            unitPrice,
                            toppingGroups,
                          ),
                    icon: _adding
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_shopping_cart),
                    label: Text(
                      'Thêm vào giỏ · ${formatVnd((unitPrice + toppingsTotal) * _quantity)}',
                    ),
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
