import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/inventory_repository.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/product_repository.dart';
import '../../widgets/image_upload_field.dart';

const productStatusLabels = {
  'draft': 'Nháp (chưa hiển thị)',
  'active': 'Đang bán',
  'out_of_stock': 'Hết hàng',
  'hidden': 'Đã ẩn',
  'archived': 'Đã xoá',
};

/// productId == null: tạo sản phẩm mới. Có id: sửa sản phẩm + quản lý biến thể.
class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _repo = ProductRepository();
  final _inventoryRepo = InventoryRepository();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'cái');
  final _priceCtrl = TextEditingController();
  final _comparePriceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _wholesalePriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  String _salesModel = 'instant';
  String _status = 'active';
  String? _imageUrl;

  Product? _product;
  Branch? _branch;
  Map<String, int> _stockByVariant = {};
  bool _loading = false;
  bool _loadingProduct = false;
  String? _error;

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _loadBranch();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _comparePriceCtrl.dispose();
    _costPriceCtrl.dispose();
    _wholesalePriceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranch() async {
    try {
      final merchant = await ref.read(myMerchantProvider.future);
      if (merchant == null) return;
      final branches = await MerchantRepository().branches(merchant.id);
      if (branches.isEmpty) return;
      final branch = branches.firstWhere((b) => b.isMain, orElse: () => branches.first);
      if (mounted) setState(() => _branch = branch);
      if (_isEdit) await _loadStock();
    } catch (_) {
      // Không chặn form nếu tạm thời không lấy được chi nhánh — chỉ ẩn phần tồn kho.
    }
  }

  Future<void> _loadStock() async {
    if (_branch == null) return;
    try {
      final items = await _inventoryRepo.list(_branch!.id);
      setState(() => _stockByVariant = {for (final i in items) i.variantId: i.quantityOnHand});
    } catch (_) {
      // bỏ qua — phần tồn kho chỉ là thông tin thêm, không chặn sửa sản phẩm
    }
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
        _status = p.status;
        _imageUrl = p.images.isNotEmpty ? p.images.first : null;
      });
      await _loadStock();
    } catch (e) {
      setState(() => _error = 'Không tải được sản phẩm: $e');
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageUrl == null) {
      setState(() => _error = 'Vui lòng thêm ảnh sản phẩm');
      return;
    }
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
          'status': _status,
          'images': [_imageUrl],
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
          status: _status,
          imageUrl: _imageUrl!,
          price: int.parse(_priceCtrl.text.trim()),
          comparePrice: int.tryParse(_comparePriceCtrl.text.trim()),
          costPrice: int.tryParse(_costPriceCtrl.text.trim()),
          wholesalePrice: int.tryParse(_wholesalePriceCtrl.text.trim()),
        );
        final stock = int.tryParse(_stockCtrl.text.trim());
        if (stock != null && stock > 0 && _branch != null && created.variants.isNotEmpty) {
          try {
            await _inventoryRepo.adjust(
              branchId: _branch!.id,
              variantId: created.variants.first.id,
              moveType: 'purchase_in',
              quantity: stock,
              note: 'Tồn kho ban đầu khi tạo sản phẩm',
            );
          } catch (_) {
            // sản phẩm đã tạo thành công — lỗi nhập kho không nên chặn điều hướng,
            // chủ cửa hàng vẫn có thể nhập lại ở màn "Biến thể & giá" hoặc "Kho hàng"
          }
        }
        if (mounted) context.pushReplacement('/products/${created.id}/edit');
      }
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _variantDialog({ProductVariant? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final comparePriceCtrl = TextEditingController(text: existing?.comparePrice?.toString() ?? '');
    final costPriceCtrl = TextEditingController(text: existing?.costPrice?.toString() ?? '');
    final wholesalePriceCtrl = TextEditingController(text: existing?.wholesalePrice?.toString() ?? '');
    final currentStock = existing != null ? (_stockByVariant[existing.id] ?? 0) : 0;
    final stockCtrl = TextEditingController(text: existing != null ? currentStock.toString() : '');
    var isActive = existing?.isActive ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(existing == null ? 'Thêm biến thể' : 'Sửa biến thể'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên (VD: 500g, 1kg)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: skuCtrl,
                    decoration: const InputDecoration(labelText: 'Mã SKU (không bắt buộc)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(labelText: 'Giá bán (VNĐ)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: comparePriceCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Giá gốc / gạch ngang (không bắt buộc)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costPriceCtrl,
                    decoration: const InputDecoration(labelText: 'Giá nhập (không bắt buộc)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: wholesalePriceCtrl,
                    decoration: const InputDecoration(labelText: 'Giá sỉ (không bắt buộc)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  if (_branch != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockCtrl,
                      decoration: InputDecoration(
                        labelText: existing == null ? 'Tồn kho ban đầu (không bắt buộc)' : 'Tồn kho hiện tại',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đang bán'),
                      value: isActive,
                      onChanged: (v) => setInner(() => isActive = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(priceCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty || price == null) return;

    try {
      if (existing == null) {
        final created = await _repo.createVariant(
          productId: widget.productId!,
          name: nameCtrl.text.trim(),
          sku: skuCtrl.text.trim(),
          price: price,
          comparePrice: int.tryParse(comparePriceCtrl.text.trim()),
          costPrice: int.tryParse(costPriceCtrl.text.trim()),
          wholesalePrice: int.tryParse(wholesalePriceCtrl.text.trim()),
          isDefault: _product?.variants.isEmpty ?? true,
        );
        final stock = int.tryParse(stockCtrl.text.trim());
        if (stock != null && stock > 0 && _branch != null) {
          await _inventoryRepo.adjust(
            branchId: _branch!.id,
            variantId: created.id,
            moveType: 'purchase_in',
            quantity: stock,
            note: 'Tồn kho ban đầu khi thêm biến thể',
          );
        }
      } else {
        await _repo.updateVariant(existing.id, {
          'name': nameCtrl.text.trim(),
          'sku': skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
          'price': price,
          'compare_price': int.tryParse(comparePriceCtrl.text.trim()),
          'cost_price': int.tryParse(costPriceCtrl.text.trim()),
          'wholesale_price': int.tryParse(wholesalePriceCtrl.text.trim()),
          'is_active': isActive,
        });
        final newStock = int.tryParse(stockCtrl.text.trim());
        final delta = (newStock ?? currentStock) - currentStock;
        if (delta != 0 && _branch != null) {
          await _inventoryRepo.adjust(
            branchId: _branch!.id,
            variantId: existing.id,
            moveType: 'adjustment',
            quantity: delta,
            note: 'Cập nhật tồn kho từ trang sản phẩm',
          );
        }
      }
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
                          decoration: const InputDecoration(labelText: 'Tên sản phẩm', border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên sản phẩm' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)', border: OutlineInputBorder()),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        ImageUploadField(
                          label: 'Ảnh sản phẩm (bắt buộc)',
                          folder: 'products',
                          initialUrl: _imageUrl,
                          onChanged: (url) => setState(() => _imageUrl = url),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _unitCtrl,
                                decoration: const InputDecoration(labelText: 'Đơn vị (kg, bó, hộp...)', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _salesModel,
                                decoration: const InputDecoration(labelText: 'Hình thức bán', border: OutlineInputBorder()),
                                items: const [
                                  DropdownMenuItem(value: 'instant', child: Text('Giao ngay')),
                                  DropdownMenuItem(value: 'scheduled', child: Text('Đặt trước / bán sỉ')),
                                ],
                                onChanged: (v) => setState(() => _salesModel = v ?? 'instant'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(labelText: 'Trạng thái sản phẩm', border: OutlineInputBorder()),
                          items: productStatusLabels.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setState(() => _status = v ?? _status),
                        ),
                        if (!_isEdit) ...[
                          const Divider(height: 32),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Giá bán', style: Theme.of(context).textTheme.labelLarge),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _priceCtrl,
                            decoration: const InputDecoration(labelText: 'Giá bán (VNĐ)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            validator: (v) => (int.tryParse(v?.trim() ?? '') == null) ? 'Nhập giá bán hợp lệ' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _comparePriceCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Giá gốc (gạch ngang)', border: OutlineInputBorder()),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _costPriceCtrl,
                                  decoration: const InputDecoration(labelText: 'Giá nhập', border: OutlineInputBorder()),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          if (_salesModel == 'scheduled') ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _wholesalePriceCtrl,
                              decoration: const InputDecoration(labelText: 'Giá sỉ', border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                          if (_branch != null) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _stockCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Tồn kho ban đầu (không bắt buộc)', border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Có thể thêm nhiều biến thể khác (size, khối lượng...) sau khi tạo sản phẩm.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_isEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm'),
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Biến thể & giá', style: Theme.of(context).textTheme.titleMedium),
                              TextButton.icon(
                                onPressed: () => _variantDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm biến thể'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if ((_product?.variants ?? []).isEmpty)
                            const Text('Chưa có biến thể nào. Khách sẽ không mua được nếu chưa có giá.')
                          else
                            ...(_product!.variants.map((v) {
                              final stock = _stockByVariant[v.id];
                              final lowStock = stock != null && stock <= 5;
                              return Card(
                                child: ListTile(
                                  title: Row(
                                    children: [
                                      Flexible(child: Text(v.name)),
                                      if (v.isDefault) ...[
                                        const SizedBox(width: 6),
                                        const Chip(label: Text('Mặc định'), visualDensity: VisualDensity.compact),
                                      ],
                                      if (!v.isActive) ...[
                                        const SizedBox(width: 6),
                                        Chip(
                                          label: const Text('Ngừng bán'),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text([
                                    formatVnd(v.price),
                                    if (v.comparePrice != null) 'Giá gốc ${formatVnd(v.comparePrice!)}',
                                    if (v.sku != null && v.sku!.isNotEmpty) 'SKU ${v.sku}',
                                    if (stock != null) 'Tồn kho: $stock${lowStock ? ' (sắp hết)' : ''}',
                                  ].join(' · ')),
                                  leading: lowStock
                                      ? const Icon(Icons.warning_amber, color: Colors.orange)
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _variantDialog(existing: v),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteVariant(v.id),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            })),
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
