import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/delivery_providers.dart';
import '../../repositories/product_repository.dart';

/// Chọn sản phẩm của 1 cửa hàng rồi báo giá thực tế (khác giá đang hiển thị) — admin duyệt ở
/// web admin (tab "Báo giá sai" trong Cửa hàng), duyệt thì áp thẳng giá mới cho sản phẩm.
class ReportPriceScreen extends ConsumerStatefulWidget {
  final String merchantId;
  const ReportPriceScreen({super.key, required this.merchantId});

  @override
  ConsumerState<ReportPriceScreen> createState() => _ReportPriceScreenState();
}

class _ReportPriceScreenState extends ConsumerState<ReportPriceScreen> {
  final _productRepo = ProductRepository();
  Product? _selected;
  final _priceCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  ProductVariant? _defaultVariant(Product p) {
    if (p.variants.isEmpty) return null;
    return p.variants.firstWhere(
      (v) => v.isDefault,
      orElse: () => p.variants.first,
    );
  }

  Future<void> _submit() async {
    final product = _selected;
    final variant = product == null ? null : _defaultVariant(product);
    if (variant == null) return;
    final reported = int.tryParse(_priceCtrl.text.trim().replaceAll('.', ''));
    if (reported == null || reported < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nhập giá thực tế hợp lệ')));
      return;
    }
    setState(() => _sending = true);
    try {
      await _productRepo.reportPrice(
        variantId: variant.id,
        reportedPrice: reported,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã gửi báo cáo — cảm ơn bạn, admin sẽ xem xét!'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(
      merchantProductPickerProvider(widget.merchantId),
    );
    final product = _selected;
    final variant = product == null ? null : _defaultVariant(product);

    return Scaffold(
      appBar: AppBar(
        title: Text(product == null ? 'Chọn sản phẩm' : 'Báo cáo giá sai'),
        leading: product == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              ),
      ),
      body: product == null
          ? productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (products) {
                final withPrice = products
                    .where((p) => _defaultVariant(p) != null)
                    .toList();
                if (withPrice.isEmpty) {
                  return const Center(child: Text('Cửa hàng chưa có sản phẩm'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: withPrice.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = withPrice[i];
                    final v = _defaultVariant(p)!;
                    return ListTile(
                      title: Text(p.name),
                      subtitle: v.name.isNotEmpty ? Text(v.name) : null,
                      trailing: Text(formatVnd(v.price)),
                      onTap: () => setState(() => _selected = p),
                    );
                  },
                );
              },
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.name}${variant!.name.isNotEmpty ? ' - ${variant.name}' : ''}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    readOnly: true,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Giá hiện tại',
                      border: OutlineInputBorder(),
                      filled: true,
                    ),
                    controller: TextEditingController(
                      text: formatVnd(variant.price),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giá thực tế',
                      border: OutlineInputBorder(),
                      suffixText: 'đ',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Gửi báo cáo'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
