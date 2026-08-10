import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';

/// templateId == null: tạo biến thể mẫu mới (thư viện dùng chung của cửa hàng — xem
/// [VariantTemplate]). Có id: sửa mẫu + quản lý bậc giá bên trong mẫu đó. Mẫu được ÁP DỤNG
/// (copy) vào sản phẩm từ màn "Thêm/sửa sản phẩm", không quản lý liên kết ở đây.
class VariantTemplateFormScreen extends ConsumerStatefulWidget {
  final String? templateId;
  const VariantTemplateFormScreen({super.key, this.templateId});

  @override
  ConsumerState<VariantTemplateFormScreen> createState() =>
      _VariantTemplateFormScreenState();
}

class _VariantTemplateFormScreenState
    extends ConsumerState<VariantTemplateFormScreen> {
  final _repo = ProductRepository();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _comparePriceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  VariantTemplate? _template;
  String _tierTab = 'wholesale'; // wholesale (Giá sỉ) | preorder (Đặt trước)
  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _comparePriceCtrl.dispose();
    _costPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await _repo.variantTemplate(widget.templateId!);
      setState(() {
        _template = t;
        _nameCtrl.text = t.name;
        _priceCtrl.text = t.price.toString();
        _comparePriceCtrl.text = t.comparePrice?.toString() ?? '';
        _costPriceCtrl.text = t.costPrice?.toString() ?? '';
      });
    } catch (e) {
      setState(() => _error = 'Không tải được biến thể mẫu: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty || price == null) {
      setState(() => _error = 'Vui lòng nhập tên và giá bán hợp lệ');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final comparePrice = int.tryParse(_comparePriceCtrl.text.trim());
      final costPrice = int.tryParse(_costPriceCtrl.text.trim());
      if (_isEdit) {
        await _repo.updateVariantTemplate(widget.templateId!, {
          'name': name,
          'price': price,
          'compare_price': comparePrice,
          'cost_price': costPrice,
        });
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Đã lưu')));
        }
      } else {
        final merchant = await ref.read(myMerchantProvider.future);
        if (merchant == null) return;
        final created = await _repo.createVariantTemplate(
          merchantId: merchant.id,
          name: name,
          price: price,
          comparePrice: comparePrice,
          costPrice: costPrice,
        );
        if (mounted) {
          context.pushReplacement('/variant-templates/${created.id}/edit');
        }
      }
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _tierDialog({WholesaleTier? existing}) async {
    final minQtyCtrl = TextEditingController(
      text: existing?.minQuantity.toString() ?? '',
    );
    final maxQtyCtrl = TextEditingController(
      text: existing?.maxQuantity?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: existing?.unitPrice.toString() ?? '',
    );
    final minDaysCtrl = TextEditingController(
      text:
          existing?.minDaysPerWeek.toString() ??
          (_tierTab == 'preorder' ? '' : '0'),
    );
    final priceDaysCtrl = TextEditingController(
      text: existing?.unitPriceDays?.toString() ?? '',
    );
    final priceBothCtrl = TextEditingController(
      text: existing?.unitPriceBoth?.toString() ?? '',
    );
    final minOrderQtyCtrl = TextEditingController(
      text: existing?.minOrderQuantity?.toString() ?? '',
    );
    final isPreorder = _tierTab == 'preorder';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Thêm bậc giá' : 'Sửa bậc giá'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: minQtyCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Số lượng tối thiểu',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxQtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số lượng tối đa (để trống = không giới hạn)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                if (isPreorder) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: minDaysCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số ngày đặt tối thiểu trong tuần',
                      helperText:
                          'Tính theo TỔNG số ngày khác nhau của cả đơn đặt trước (gộp mọi sản phẩm khách đặt cùng đơn), không phải riêng sản phẩm này',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Giá theo từng điều kiện đạt được',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chỉ đạt điều kiện số lượng (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceDaysCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chỉ đạt điều kiện số ngày tối thiểu (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceBothCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đạt cả 2 điều kiện (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đơn giá (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minOrderQtyCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'Hoặc số lượng tối thiểu CẢ ĐƠN (không bắt buộc)',
                      helperText:
                          'Nếu tổng số lượng mọi sản phẩm trong đơn đạt số này, sản phẩm '
                          'vẫn được giá bậc này dù số lượng riêng chưa đạt ở trên',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final minQty = int.tryParse(minQtyCtrl.text.trim());
    final price = int.tryParse(priceCtrl.text.trim());
    if (minQty == null || price == null) return;
    final maxQty = int.tryParse(maxQtyCtrl.text.trim());
    final minDays = isPreorder
        ? (int.tryParse(minDaysCtrl.text.trim()) ?? 0)
        : 0;
    final priceDays = isPreorder
        ? int.tryParse(priceDaysCtrl.text.trim())
        : null;
    final priceBoth = isPreorder
        ? int.tryParse(priceBothCtrl.text.trim())
        : null;
    final minOrderQty = isPreorder
        ? null
        : int.tryParse(minOrderQtyCtrl.text.trim());

    if (minQty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Số lượng tối thiểu phải lớn hơn 0')),
        );
      }
      return;
    }
    if (maxQty != null && maxQty < minQty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Số lượng tối đa phải lớn hơn hoặc bằng số lượng tối thiểu',
            ),
          ),
        );
      }
      return;
    }
    if (minOrderQty != null && minOrderQty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Số lượng tối thiểu cả đơn phải lớn hơn 0'),
          ),
        );
      }
      return;
    }
    if (isPreorder && (priceDays == null || priceBoth == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vui lòng nhập đủ 3 mức giá theo điều kiện'),
          ),
        );
      }
      return;
    }

    try {
      if (existing == null) {
        await _repo.createVariantTemplateTier(
          templateId: widget.templateId!,
          minQuantity: minQty,
          maxQuantity: maxQty,
          unitPrice: price,
          minDaysPerWeek: minDays,
          unitPriceDays: priceDays,
          unitPriceBoth: priceBoth,
          minOrderQuantity: minOrderQty,
        );
      } else {
        await _repo.updateVariantTemplateTier(existing.id, {
          'min_quantity': minQty,
          'max_quantity': maxQty,
          'unit_price': price,
          'min_days_per_week': minDays,
          'unit_price_days': priceDays,
          'unit_price_both': priceBoth,
          'min_order_quantity': minOrderQty,
        });
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteTier(WholesaleTier tier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá bậc giá?'),
        content: Text(
          'Xoá bậc giá cho số lượng từ ${tier.minQuantity} trở lên?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteVariantTemplateTier(tier.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Widget _tierSection() {
    final allTiers = _template?.wholesaleTiers ?? const <WholesaleTier>[];
    final tiers =
        allTiers
            .where(
              (t) => _tierTab == 'preorder'
                  ? t.minDaysPerWeek > 0
                  : t.minDaysPerWeek == 0,
            )
            .toList()
          ..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Bậc giá', style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: () => _tierDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm bậc'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'wholesale', label: Text('Giá sỉ')),
            ButtonSegment(value: 'preorder', label: Text('Đặt trước')),
          ],
          selected: {_tierTab},
          onSelectionChanged: (v) => setState(() => _tierTab = v.first),
        ),
        const SizedBox(height: 8),
        if (tiers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Text('Chưa có bậc giá nào.'),
          )
        else
          ...tiers.map(
            (t) => Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  t.maxQuantity != null
                      ? 'Số lượng ${t.minQuantity}–${t.maxQuantity}'
                      : 'Số lượng từ ${t.minQuantity}',
                ),
                subtitle: _tierTab == 'preorder'
                    ? Text(
                        'SL: ${formatVnd(t.unitPrice)} · '
                        '≥${t.minDaysPerWeek} ngày/tuần: ${formatVnd(t.unitPriceDays ?? 0)} · '
                        'Cả 2: ${formatVnd(t.unitPriceBoth ?? 0)}',
                      )
                    : Text(
                        t.minOrderQuantity != null
                            ? '${formatVnd(t.unitPrice)} (hoặc cả đơn ≥ ${t.minOrderQuantity})'
                            : formatVnd(t.unitPrice),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _tierDialog(existing: t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteTier(t),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa biến thể mẫu' : 'Thêm biến thể mẫu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dùng chung cho nhiều sản phẩm — chọn mẫu này lúc thêm biến thể cho 1 '
                    'sản phẩm sẽ COPY tên/giá/bậc giá vào sản phẩm đó, bạn có thể chỉnh lại '
                    'giá riêng cho từng sản phẩm sau khi copy.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    autofocus: !_isEdit,
                    decoration: const InputDecoration(
                      labelText: 'Tên (VD: 500g, 1kg, Size L)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá bán (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _comparePriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá gốc / gạch ngang (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _costPriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá nhập (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEdit ? 'Lưu' : 'Tạo mẫu'),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 8),
                    _tierSection(),
                  ],
                ],
              ),
            ),
    );
  }
}
