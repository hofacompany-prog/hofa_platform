import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';

/// productId == null: tạo sản phẩm mới. Có id: sửa sản phẩm + quản lý biến thể.
class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _repo = ProductRepository();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'cái');
  String _salesModel = 'instant';

  Product? _product;
  bool _loading = false;
  bool _loadingProduct = false;
  String? _error;

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loadingProduct = true);
    try {
      final p = await _repo.get(widget.productId!);
      setState(() {
        _product = p;
        _nameCtrl.text = p.name;
        _descCtrl.text = p.description ?? '';
        _unitCtrl.text = p.unit;
        _salesModel = p.salesModel;
      });
    } catch (e) {
      setState(() => _error = 'Không tải được sản phẩm: $e');
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await _repo.update(widget.productId!, {
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'unit': _unitCtrl.text.trim(),
          'sales_model': _salesModel,
        });
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu')));
        }
      } else {
        final merchant = await ref.read(myMerchantProvider.future);
        if (merchant == null) return;
        final created = await _repo.create(
          merchantId: merchant.id,
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          salesModel: _salesModel,
        );
        if (mounted) context.pushReplacement('/products/${created.id}/edit');
      }
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addVariantDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm biến thể'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên (VD: 500g, 1kg)')),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Giá bán (VNĐ)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thêm')),
        ],
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(priceCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty || price == null) return;
    try {
      await _repo.createVariant(
        productId: widget.productId!,
        name: nameCtrl.text.trim(),
        price: price,
        isDefault: _product?.variants.isEmpty ?? true,
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _deleteVariant(String id) async {
    try {
      await _repo.deleteVariant(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa sản phẩm' : 'Thêm sản phẩm')),
      body: _loadingProduct
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên sản phẩm' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)'),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _unitCtrl,
                                decoration: const InputDecoration(labelText: 'Đơn vị (kg, bó, hộp...)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _salesModel,
                                decoration: const InputDecoration(labelText: 'Hình thức bán'),
                                items: const [
                                  DropdownMenuItem(value: 'instant', child: Text('Giao ngay')),
                                  DropdownMenuItem(value: 'scheduled', child: Text('Đặt trước / bán sỉ')),
                                ],
                                onChanged: (v) => setState(() => _salesModel = v ?? 'instant'),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_isEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm, thêm giá sau'),
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Biến thể & giá', style: Theme.of(context).textTheme.titleMedium),
                              TextButton.icon(
                                onPressed: _addVariantDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm biến thể'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if ((_product?.variants ?? []).isEmpty)
                            const Text('Chưa có biến thể nào. Khách sẽ không mua được nếu chưa có giá.')
                          else
                            ...(_product!.variants.map((v) => Card(
                                  child: ListTile(
                                    title: Text(v.name),
                                    subtitle: Text(formatVnd(v.price)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _deleteVariant(v.id),
                                    ),
                                  ),
                                ))),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
