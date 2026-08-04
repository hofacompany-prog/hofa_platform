import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/branch.dart';
import '../../models/category.dart';
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
  final _stockCtrl = TextEditingController();
  String _salesModel = 'instant';
  String _status = 'active';
  String? _imageUrl;

  Product? _product;
  Branch? _branch;
  Map<String, int> _stockByVariant = {};
  List<ToppingGroup> _toppingGroups = [];
  // _tiersByVariant: khi sửa sản phẩm khoá bằng id biến thể thật; khi tạo mới khoá bằng
  // 'default' (biến thể mặc định lấy giá từ khung "Giá bán") hoặc id tạm của _pendingVariants.
  Map<String, List<WholesaleTier>> _tiersByVariant = {};
  List<ProductVariant> _pendingVariants =
      []; // biến thể thêm lúc tạo mới, chưa có id thật
  String _tierTab = 'wholesale'; // wholesale (Giá sỉ) | preorder (Đặt trước)
  bool _loading = false;
  bool _loadingProduct = false;
  String? _error;

  String? _merchantId;
  List<Category> _allCategories = [];
  List<MerchantCategory> _merchantCategories = [];
  String? _parentCategoryId;
  String? _childCategoryId;
  String? _merchantCategoryId;

  List<Category> get _rootCategories =>
      _allCategories.where((c) => c.parentId == null).toList();

  List<Category> _childCategoriesOf(String parentId) =>
      _allCategories.where((c) => c.parentId == parentId).toList();

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    _loadBranch();
    if (_isEdit) {
      _load();
    } else {
      _initCategoryPicker();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranch() async {
    try {
      final merchant = await ref.read(myMerchantProvider.future);
      if (merchant == null) return;
      final branches = await MerchantRepository().branches(merchant.id);
      if (branches.isEmpty) return;
      final branch = branches.firstWhere(
        (b) => b.isMain,
        orElse: () => branches.first,
      );
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
      setState(
        () => _stockByVariant = {
          for (final i in items) i.variantId: i.quantityOnHand,
        },
      );
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
      await _loadToppingGroups();
      await _loadWholesaleTiers();
      await _initCategoryPicker();
    } catch (e) {
      setState(() => _error = 'Không tải được sản phẩm: $e');
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  Future<void> _loadWholesaleTiers() async {
    if (_product == null || _salesModel != 'scheduled') return;
    try {
      final entries = await Future.wait(
        _product!.variants.map(
          (v) async => MapEntry(v.id, await _repo.wholesaleTiers(v.id)),
        ),
      );
      if (mounted) {
        setState(
          () => _tiersByVariant = {for (final e in entries) e.key: e.value},
        );
      }
    } catch (_) {
      // bậc giá chỉ là thông tin thêm, không chặn sửa sản phẩm
    }
  }

  Future<void> _tierDialog({String? variantId, WholesaleTier? existing}) async {
    // 1 biến thể chỉ được 1 trong 2 loại bậc giá — chặn thêm mới nếu biến thể đã có bậc
    // loại kia (nút "Thêm bậc" cũng đã khoá ở _tierVariantCard, đây là chặn thêm lần nữa
    // cho chắc). Sửa bậc có sẵn (existing != null) thì không cần chặn vì không đổi loại.
    if (existing == null) {
      final key = variantId ?? 'default';
      final currentTiers = _tiersByVariant[key] ?? [];
      final hasOtherType = currentTiers.any(
        (t) => (t.leadTimeDays > 0) != (_tierTab == 'preorder'),
      );
      if (hasOtherType) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _tierTab == 'preorder'
                    ? 'Biến thể này đã có bậc giá sỉ — xoá hết trước khi thêm đặt trước'
                    : 'Biến thể này đã có bậc đặt trước — xoá hết trước khi thêm giá sỉ',
              ),
            ),
          );
        }
        return;
      }
    }

    final minQtyCtrl = TextEditingController(
      text: existing?.minQuantity.toString() ?? '',
    );
    final maxQtyCtrl = TextEditingController(
      text: existing?.maxQuantity?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: existing?.unitPrice.toString() ?? '',
    );
    final leadDaysCtrl = TextEditingController(
      text:
          existing?.leadTimeDays.toString() ??
          (_tierTab == 'preorder' ? '' : '0'),
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
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Đơn giá (VNĐ)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                if (isPreorder) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: leadDaysCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đặt trước tối thiểu bao nhiêu ngày',
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
    final leadDays = isPreorder
        ? (int.tryParse(leadDaysCtrl.text.trim()) ?? 0)
        : 0;

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

    // Chưa tạo sản phẩm (đang ở màn "Thêm sản phẩm") — chưa có variant_id thật để gọi API,
    // giữ tạm bậc giá trong bộ nhớ theo khoá 'default'/id tạm của biến thể, gửi kèm lên
    // cùng lúc tạo sản phẩm lúc bấm "Tạo sản phẩm" (xem _submit).
    if (!_isEdit) {
      final key = variantId ?? 'default';
      setState(() {
        final current = _tiersByVariant[key] ?? [];
        if (existing == null) {
          _tiersByVariant = {
            ..._tiersByVariant,
            key: [
              ...current,
              WholesaleTier(
                id: 'local-${DateTime.now().microsecondsSinceEpoch}',
                variantId: key,
                minQuantity: minQty,
                maxQuantity: maxQty,
                unitPrice: price,
                leadTimeDays: leadDays,
              ),
            ],
          };
        } else {
          _tiersByVariant = {
            ..._tiersByVariant,
            key: current
                .map(
                  (t) => t.id == existing.id
                      ? WholesaleTier(
                          id: t.id,
                          variantId: t.variantId,
                          minQuantity: minQty,
                          maxQuantity: maxQty,
                          unitPrice: price,
                          leadTimeDays: leadDays,
                        )
                      : t,
                )
                .toList(),
          };
        }
      });
      return;
    }

    try {
      if (existing == null) {
        await _repo.createWholesaleTier(
          variantId: variantId!,
          minQuantity: minQty,
          maxQuantity: maxQty,
          unitPrice: price,
          leadTimeDays: leadDays,
        );
      } else {
        await _repo.updateWholesaleTier(existing.id, {
          'min_quantity': minQty,
          'max_quantity': maxQty,
          'unit_price': price,
          'lead_time_days': leadDays,
        });
      }
      await _loadWholesaleTiers();
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

    if (!_isEdit) {
      final key = tier.variantId;
      setState(
        () => _tiersByVariant = {
          ..._tiersByVariant,
          key: (_tiersByVariant[key] ?? [])
              .where((t) => t.id != tier.id)
              .toList(),
        },
      );
      return;
    }

    try {
      await _repo.deleteWholesaleTier(tier.id);
      await _loadWholesaleTiers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  /// [variantId] là id thật (đang sửa sản phẩm) hoặc 'default'/id tạm của biến thể đang
  /// chờ tạo (đang thêm sản phẩm) — cả 2 trường hợp đều đọc/ghi vào [_tiersByVariant].
  Widget _tierVariantCard({
    required String? variantId,
    required String? title,
    required List<WholesaleTier> allTiers,
  }) {
    final tiers =
        allTiers
            .where(
              (t) => _tierTab == 'preorder'
                  ? t.leadTimeDays > 0
                  : t.leadTimeDays == 0,
            )
            .toList()
          ..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
    // 1 biến thể chỉ được 1 trong 2 loại bậc giá — đã có bậc loại kia thì khoá nút thêm
    // của tab hiện tại lại, tránh trộn giá sỉ + đặt trước trên cùng 1 biến thể.
    final hasOtherType = allTiers.any(
      (t) => (t.leadTimeDays > 0) != (_tierTab == 'preorder'),
    );
    final addButton = TextButton.icon(
      onPressed: hasOtherType ? null : () => _tierDialog(variantId: variantId),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Thêm bậc'),
    );

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  addButton,
                ],
              )
            else
              Align(alignment: Alignment.centerRight, child: addButton),
            if (hasOtherType)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  _tierTab == 'preorder'
                      ? 'Biến thể này đang dùng giá sỉ — xoá hết bậc giá sỉ để đổi sang đặt trước'
                      : 'Biến thể này đang dùng đặt trước — xoá hết bậc đặt trước để đổi sang giá sỉ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              )
            else if (tiers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'Chưa có bậc giá nào.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...tiers.map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.maxQuantity != null
                        ? 'Số lượng ${t.minQuantity}–${t.maxQuantity}'
                        : 'Số lượng từ ${t.minQuantity}',
                  ),
                  subtitle: Text(
                    [
                      formatVnd(t.unitPrice),
                      if (_tierTab == 'preorder')
                        'Đặt trước ≥ ${t.leadTimeDays} ngày',
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () =>
                            _tierDialog(variantId: variantId, existing: t),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteTier(t),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Nạp cây danh mục hệ thống (chính/con) + nếu đang sửa sản phẩm đã có danh mục cửa
  /// hàng, dò ngược lại danh mục con → danh mục chính tương ứng để chọn sẵn 3 tầng.
  Future<void> _initCategoryPicker() async {
    try {
      final merchant = await ref.read(myMerchantProvider.future);
      if (merchant == null) return;
      _merchantId = merchant.id;
      final all = await _repo.categories();
      if (!mounted) return;
      setState(() => _allCategories = all);

      final mcId = _product?.merchantCategoryId;
      if (mcId == null) return;
      final mine = await _repo.merchantCategories(merchantId: merchant.id);
      final matched = mine.where((m) => m.id == mcId);
      if (matched.isEmpty) return;
      final childId = matched.first.categoryId;
      final child = all.where((c) => c.id == childId);
      if (!mounted) return;
      setState(() {
        _childCategoryId = childId;
        _parentCategoryId = child.isNotEmpty ? child.first.parentId : null;
        _merchantCategoryId = mcId;
        _merchantCategories = mine
            .where((m) => m.categoryId == childId)
            .toList();
      });
    } catch (_) {
      // danh mục chỉ là thông tin thêm, không chặn thêm/sửa sản phẩm
    }
  }

  Future<void> _loadMerchantCategoriesFor(String categoryId) async {
    if (_merchantId == null) return;
    try {
      final list = await _repo.merchantCategories(
        merchantId: _merchantId!,
        categoryId: categoryId,
      );
      if (mounted) setState(() => _merchantCategories = list);
    } catch (_) {
      // bỏ qua — chọn danh mục cửa hàng không bắt buộc
    }
  }

  Future<void> _addMerchantCategoryDialog() async {
    if (_merchantId == null || _childCategoryId == null) return;
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm danh mục cửa hàng'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên danh mục (VD: Cà phê máy, Trà trái cây)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      final created = await _repo.createMerchantCategory(
        merchantId: _merchantId!,
        categoryId: _childCategoryId!,
        name: nameCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _merchantCategories = [..._merchantCategories, created];
          _merchantCategoryId = created.id;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _loadToppingGroups() async {
    try {
      final groups = await _repo.toppingGroups(widget.productId!);
      if (mounted) setState(() => _toppingGroups = groups);
    } catch (_) {
      // bỏ qua — phần topping chỉ là tuỳ chọn thêm, không chặn sửa sản phẩm
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
          'merchant_category_id': _merchantCategoryId,
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
        final created = await _repo.create(
          merchantId: merchant.id,
          merchantCategoryId: _merchantCategoryId,
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          salesModel: _salesModel,
          status: _status,
          imageUrl: _imageUrl!,
          price: int.parse(_priceCtrl.text.trim()),
          toppingGroups: _toppingGroups,
          wholesaleTiers: _tiersByVariant['default'] ?? [],
          extraVariants: _pendingVariants,
          tiersByVariant: _tiersByVariant,
        );
        final stock = int.tryParse(_stockCtrl.text.trim());
        if (stock != null &&
            stock > 0 &&
            _branch != null &&
            created.variants.isNotEmpty) {
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
    final priceCtrl = TextEditingController(
      text: existing?.price.toString() ?? '',
    );
    final comparePriceCtrl = TextEditingController(
      text: existing?.comparePrice?.toString() ?? '',
    );
    final costPriceCtrl = TextEditingController(
      text: existing?.costPrice?.toString() ?? '',
    );
    final currentStock = existing != null
        ? (_stockByVariant[existing.id] ?? 0)
        : 0;
    final stockCtrl = TextEditingController(
      text: existing != null ? currentStock.toString() : '',
    );
    var isActive = existing?.isActive ?? true;
    var isDefault = existing?.isDefault ?? false;

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
                    decoration: const InputDecoration(
                      labelText: 'Tên (VD: 500g, 1kg)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: skuCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã SKU (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá bán (VNĐ)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: comparePriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá gốc / gạch ngang (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costPriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giá nhập (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (_branch != null && _isEdit) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockCtrl,
                      decoration: InputDecoration(
                        labelText: existing == null
                            ? 'Tồn kho ban đầu (không bắt buộc)'
                            : 'Tồn kho hiện tại',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (existing != null && _isEdit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đặt làm mặc định'),
                      subtitle: const Text(
                        'Biến thể mặc định hiển thị đầu tiên — bật sẽ tự tắt mặc định của biến thể khác',
                      ),
                      value: isDefault,
                      onChanged: (v) => setInner(() => isDefault = v),
                    ),
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
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(priceCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty || price == null) return;

    // Chưa tạo sản phẩm (đang ở màn "Thêm sản phẩm") — chưa có product_id để gọi API,
    // giữ tạm biến thể trong bộ nhớ, gửi kèm lên cùng lúc tạo sản phẩm lúc bấm "Tạo sản
    // phẩm" (xem _submit). Đây luôn là biến thể THÊM (biến thể mặc định lấy từ khung
    // "Giá bán" phía trên).
    if (!_isEdit) {
      final comparePrice = int.tryParse(comparePriceCtrl.text.trim());
      final costPrice = int.tryParse(costPriceCtrl.text.trim());
      final sku = skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim();
      setState(() {
        if (existing == null) {
          _pendingVariants = [
            ..._pendingVariants,
            ProductVariant(
              id: 'local-${DateTime.now().microsecondsSinceEpoch}',
              productId: '',
              sku: sku,
              name: nameCtrl.text.trim(),
              price: price,
              comparePrice: comparePrice,
              costPrice: costPrice,
              isDefault: false,
              isActive: true,
            ),
          ];
        } else {
          _pendingVariants = _pendingVariants
              .map(
                (v) => v.id == existing.id
                    ? ProductVariant(
                        id: v.id,
                        productId: v.productId,
                        sku: sku,
                        name: nameCtrl.text.trim(),
                        price: price,
                        comparePrice: comparePrice,
                        costPrice: costPrice,
                        isDefault: v.isDefault,
                        isActive: v.isActive,
                      )
                    : v,
              )
              .toList();
        }
      });
      return;
    }

    try {
      if (existing == null) {
        final created = await _repo.createVariant(
          productId: widget.productId!,
          name: nameCtrl.text.trim(),
          sku: skuCtrl.text.trim(),
          price: price,
          comparePrice: int.tryParse(comparePriceCtrl.text.trim()),
          costPrice: int.tryParse(costPriceCtrl.text.trim()),
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
          'is_active': isActive,
          'is_default': isDefault,
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteVariant(String id) async {
    if (!_isEdit) {
      setState(
        () => _pendingVariants = _pendingVariants
            .where((v) => v.id != id)
            .toList(),
      );
      return;
    }
    try {
      await _repo.deleteVariant(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _toppingGroupDialog({ToppingGroup? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var isRequired = existing?.isRequired ?? false;
    var allowMultiple = existing?.allowMultiple ?? false;
    // Toppings sẽ được nhân bản kèm theo nếu bấm "Dán" — chỉ có ý nghĩa lúc TẠO nhóm mới.
    var pasteToppings = const <Topping>[];
    final copiedGroup = existing == null
        ? ref.read(copiedToppingGroupProvider)
        : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(
            existing == null ? 'Thêm nhóm topping' : 'Sửa nhóm topping',
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (copiedGroup != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => setInner(() {
                          nameCtrl.text = copiedGroup.name;
                          isRequired = copiedGroup.isRequired;
                          allowMultiple = copiedGroup.allowMultiple;
                          pasteToppings = copiedGroup.toppings;
                        }),
                        icon: const Icon(Icons.content_paste),
                        label: Text(
                          'Dán "${copiedGroup.name}" (${copiedGroup.toppings.length} lựa chọn)',
                        ),
                      ),
                    ),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm (VD: Chọn topping, Độ ngọt)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bắt buộc chọn'),
                    subtitle: const Text(
                      'Khách phải chọn ít nhất 1 mục trong nhóm này',
                    ),
                    value: isRequired,
                    onChanged: (v) => setInner(() => isRequired = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho chọn nhiều mục'),
                    subtitle: const Text(
                      'Bật: chọn nhiều · Tắt: chỉ chọn 1 trong nhóm',
                    ),
                    value: allowMultiple,
                    onChanged: (v) => setInner(() => allowMultiple = v),
                  ),
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
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    // Chưa tạo sản phẩm (đang ở màn "Thêm sản phẩm") — chưa có product_id để gọi API,
    // giữ tạm nhóm topping trong bộ nhớ, gửi kèm lên cùng lúc tạo sản phẩm lúc bấm "Tạo
    // sản phẩm" (xem _submit).
    if (!_isEdit) {
      setState(() {
        if (existing == null) {
          final newGroupId = 'local-${DateTime.now().microsecondsSinceEpoch}';
          _toppingGroups = [
            ..._toppingGroups,
            ToppingGroup(
              id: newGroupId,
              productId: '',
              name: nameCtrl.text.trim(),
              isRequired: isRequired,
              allowMultiple: allowMultiple,
              sortOrder: _toppingGroups.length,
              toppings: [
                for (final entry in pasteToppings.asMap().entries)
                  Topping(
                    id: 'local-${DateTime.now().microsecondsSinceEpoch}-${entry.key}',
                    groupId: newGroupId,
                    name: entry.value.name,
                    price: entry.value.price,
                    sortOrder: entry.key,
                  ),
              ],
            ),
          ];
        } else {
          _toppingGroups = _toppingGroups
              .map(
                (g) => g.id == existing.id
                    ? ToppingGroup(
                        id: g.id,
                        productId: g.productId,
                        name: nameCtrl.text.trim(),
                        isRequired: isRequired,
                        allowMultiple: allowMultiple,
                        sortOrder: g.sortOrder,
                        toppings: g.toppings,
                      )
                    : g,
              )
              .toList();
        }
      });
      return;
    }

    try {
      if (existing == null) {
        final createdGroup = await _repo.createToppingGroup(
          productId: widget.productId!,
          name: nameCtrl.text.trim(),
          isRequired: isRequired,
          allowMultiple: allowMultiple,
        );
        for (final t in pasteToppings) {
          await _repo.createTopping(
            groupId: createdGroup.id,
            name: t.name,
            price: t.price,
          );
        }
      } else {
        await _repo.updateToppingGroup(existing.id, {
          'name': nameCtrl.text.trim(),
          'is_required': isRequired,
          'allow_multiple': allowMultiple,
        });
      }
      await _loadToppingGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  void _copyToppingGroup(ToppingGroup group) {
    ref.read(copiedToppingGroupProvider.notifier).state = group;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã sao chép nhóm "${group.name}" — bấm "Thêm nhóm" ở sản phẩm bất kỳ để dán lại.',
        ),
      ),
    );
  }

  Future<void> _deleteToppingGroup(ToppingGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá nhóm topping?'),
        content: Text(
          'Xoá nhóm "${group.name}" sẽ xoá luôn ${group.toppings.length} lựa chọn bên trong.',
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

    if (!_isEdit) {
      setState(
        () => _toppingGroups = _toppingGroups
            .where((g) => g.id != group.id)
            .toList(),
      );
      return;
    }

    try {
      await _repo.deleteToppingGroup(group.id);
      await _loadToppingGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _toppingDialog({
    required String groupId,
    Topping? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing?.price.toString() ?? '0',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Thêm lựa chọn' : 'Sửa lựa chọn'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên (VD: Trân châu đen)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Giá cộng thêm (VNĐ, để 0 nếu miễn phí)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
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
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final price = int.tryParse(priceCtrl.text.trim()) ?? 0;

    if (!_isEdit) {
      setState(() {
        _toppingGroups = _toppingGroups.map((g) {
          if (g.id != groupId) return g;
          final newToppings = existing == null
              ? [
                  ...g.toppings,
                  Topping(
                    id: 'local-${DateTime.now().microsecondsSinceEpoch}',
                    groupId: g.id,
                    name: nameCtrl.text.trim(),
                    price: price,
                    sortOrder: g.toppings.length,
                  ),
                ]
              : g.toppings
                    .map(
                      (t) => t.id == existing.id
                          ? Topping(
                              id: t.id,
                              groupId: t.groupId,
                              name: nameCtrl.text.trim(),
                              price: price,
                              sortOrder: t.sortOrder,
                            )
                          : t,
                    )
                    .toList();
          return ToppingGroup(
            id: g.id,
            productId: g.productId,
            name: g.name,
            isRequired: g.isRequired,
            allowMultiple: g.allowMultiple,
            sortOrder: g.sortOrder,
            toppings: newToppings,
          );
        }).toList();
      });
      return;
    }

    try {
      if (existing == null) {
        await _repo.createTopping(
          groupId: groupId,
          name: nameCtrl.text.trim(),
          price: price,
        );
      } else {
        await _repo.updateTopping(existing.id, {
          'name': nameCtrl.text.trim(),
          'price': price,
        });
      }
      await _loadToppingGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _deleteTopping(String groupId, String toppingId) async {
    if (!_isEdit) {
      setState(() {
        _toppingGroups = _toppingGroups.map((g) {
          if (g.id != groupId) return g;
          return ToppingGroup(
            id: g.id,
            productId: g.productId,
            name: g.name,
            isRequired: g.isRequired,
            allowMultiple: g.allowMultiple,
            sortOrder: g.sortOrder,
            toppings: g.toppings.where((t) => t.id != toppingId).toList(),
          );
        }).toList();
      });
      return;
    }

    try {
      await _repo.deleteTopping(toppingId);
      await _loadToppingGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
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
                          decoration: const InputDecoration(
                            labelText: 'Tên sản phẩm',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Nhập tên sản phẩm'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Mô tả (không bắt buộc)',
                            border: OutlineInputBorder(),
                          ),
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
                                decoration: const InputDecoration(
                                  labelText: 'Đơn vị (kg, bó, hộp...)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _salesModel,
                                decoration: const InputDecoration(
                                  labelText: 'Hình thức bán',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'instant',
                                    child: Text('Giao ngay'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'scheduled',
                                    child: Text('Đặt trước / bán sỉ'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() => _salesModel = v ?? 'instant');
                                  if (_isEdit && _salesModel == 'scheduled') {
                                    _loadWholesaleTiers();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Trạng thái sản phẩm',
                            border: OutlineInputBorder(),
                          ),
                          items: productStatusLabels.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _status = v ?? _status),
                        ),
                        const Divider(height: 32),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Danh mục',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chọn danh mục chính → danh mục con của hệ thống, sau đó chọn hoặc tạo danh mục riêng của cửa hàng bạn — khách chỉ thấy danh mục cửa hàng, không thấy danh mục chính/con.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _parentCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Danh mục chính',
                            border: OutlineInputBorder(),
                          ),
                          items: _rootCategories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            _parentCategoryId = v;
                            _childCategoryId = null;
                            _merchantCategoryId = null;
                            _merchantCategories = [];
                          }),
                        ),
                        if (_parentCategoryId != null) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _childCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'Danh mục con',
                              border: OutlineInputBorder(),
                            ),
                            items: _childCategoriesOf(_parentCategoryId!)
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _childCategoryId = v;
                                _merchantCategoryId = null;
                                _merchantCategories = [];
                              });
                              if (v != null) _loadMerchantCategoriesFor(v);
                            },
                          ),
                        ],
                        if (_childCategoryId != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _merchantCategoryId,
                                  decoration: const InputDecoration(
                                    labelText: 'Danh mục cửa hàng',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _merchantCategories
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c.id,
                                          child: Text(c.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _merchantCategoryId = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Thêm danh mục cửa hàng mới',
                                icon: const Icon(Icons.add),
                                onPressed: _addMerchantCategoryDialog,
                              ),
                            ],
                          ),
                          if (_merchantCategories.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Cửa hàng chưa có danh mục nào trong nhóm này — bấm nút + để tạo mới.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                        if (!_isEdit) ...[
                          const Divider(height: 32),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Giá bán',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _priceCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Giá bán (VNĐ)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (int.tryParse(v?.trim() ?? '') == null)
                                ? 'Nhập giá bán hợp lệ'
                                : null,
                          ),
                          if (_branch != null) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _stockCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Tồn kho ban đầu (không bắt buộc)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Biến thể khác (không bắt buộc)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              TextButton.icon(
                                onPressed: () => _variantDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm biến thể'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Giá ở trên là biến thể mặc định (VD: 500g) — thêm biến thể khác nếu sản phẩm có nhiều lựa chọn (VD: 1kg, 2kg) ngay từ lúc tạo.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          if (_pendingVariants.isEmpty)
                            const Text('Chưa có biến thể nào khác.')
                          else
                            ..._pendingVariants.map(
                              (v) => Card(
                                child: ListTile(
                                  title: Text(v.name),
                                  subtitle: Text(formatVnd(v.price)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            _variantDialog(existing: v),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteVariant(v.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                        if (_isEdit) ...[
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Biến thể & giá',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              TextButton.icon(
                                onPressed: () => _variantDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm biến thể'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if ((_product?.variants ?? []).isEmpty)
                            const Text(
                              'Chưa có biến thể nào. Khách sẽ không mua được nếu chưa có giá.',
                            )
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
                                        const Chip(
                                          label: Text('Mặc định'),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                      if (!v.isActive) ...[
                                        const SizedBox(width: 6),
                                        Chip(
                                          label: const Text('Ngừng bán'),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.errorContainer,
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    [
                                      formatVnd(v.price),
                                      if (v.comparePrice != null)
                                        'Giá gốc ${formatVnd(v.comparePrice!)}',
                                      if (v.sku != null && v.sku!.isNotEmpty)
                                        'SKU ${v.sku}',
                                      if (stock != null)
                                        'Tồn kho: $stock${lowStock ? ' (sắp hết)' : ''}',
                                    ].join(' · '),
                                  ),
                                  leading: lowStock
                                      ? const Icon(
                                          Icons.warning_amber,
                                          color: Colors.orange,
                                        )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            _variantDialog(existing: v),
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
                        if (_salesModel == 'scheduled') ...[
                          const SizedBox(height: 32),
                          Text(
                            'Bậc giá theo số lượng',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '"Giá sỉ" chỉ theo số lượng mua · "Đặt trước" có thêm điều kiện đặt trước tối thiểu bao nhiêu ngày. Mỗi biến thể tự cài đặt bậc giá riêng.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Giá sỉ'),
                                selected: _tierTab == 'wholesale',
                                onSelected: (_) =>
                                    setState(() => _tierTab = 'wholesale'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Đặt trước'),
                                selected: _tierTab == 'preorder',
                                onSelected: (_) =>
                                    setState(() => _tierTab = 'preorder'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isEdit)
                            if ((_product?.variants ?? []).isEmpty)
                              const Text(
                                'Chưa có biến thể nào — thêm biến thể ở trên trước.',
                              )
                            else
                              ...(_product!.variants.map(
                                (v) => _tierVariantCard(
                                  variantId: v.id,
                                  title: v.name,
                                  allTiers: _tiersByVariant[v.id] ?? [],
                                ),
                              ))
                          else
                            ...[
                              ProductVariant(
                                id: 'default',
                                productId: '',
                                name: _unitCtrl.text.trim().isEmpty
                                    ? 'Mặc định'
                                    : _unitCtrl.text.trim(),
                                price:
                                    int.tryParse(_priceCtrl.text.trim()) ?? 0,
                                isDefault: true,
                                isActive: true,
                              ),
                              ..._pendingVariants,
                            ].map(
                              (v) => _tierVariantCard(
                                variantId: v.id,
                                title: v.name,
                                allTiers: _tiersByVariant[v.id] ?? [],
                              ),
                            ),
                        ],
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Topping & tuỳ chọn thêm',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            TextButton.icon(
                              onPressed: () => _toppingGroupDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm nhóm'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'VD: "Chọn topping" (chọn nhiều, không bắt buộc), "Size" (chỉ chọn 1, bắt buộc).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        if (_toppingGroups.isEmpty)
                          const Text(
                            'Chưa có nhóm topping nào. Sản phẩm vẫn bán bình thường nếu không cần.',
                          )
                        else
                          ..._toppingGroups.map(
                            (g) => Card(
                              elevation: 0,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  8,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                g.name,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              if (g.isRequired)
                                                Chip(
                                                  label: const Text('Bắt buộc'),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  backgroundColor: Theme.of(
                                                    context,
                                                  ).colorScheme.errorContainer,
                                                ),
                                              Chip(
                                                label: Text(
                                                  g.allowMultiple
                                                      ? 'Chọn nhiều'
                                                      : 'Chọn 1',
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Sao chép nhóm này',
                                          icon: const Icon(Icons.copy_outlined),
                                          onPressed: () => _copyToppingGroup(g),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              _toppingGroupDialog(existing: g);
                                            }
                                            if (v == 'delete') {
                                              _deleteToppingGroup(g);
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Sửa nhóm'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Xoá nhóm'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (g.toppings.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          'Chưa có lựa chọn nào trong nhóm này.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      )
                                    else
                                      ...g.toppings.map(
                                        (t) => ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(t.name),
                                          subtitle: Text(
                                            t.price > 0
                                                ? '+${formatVnd(t.price)}'
                                                : 'Miễn phí',
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 20,
                                                ),
                                                onPressed: () => _toppingDialog(
                                                  groupId: g.id,
                                                  existing: t,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _deleteTopping(g.id, t.id),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            _toppingDialog(groupId: g.id),
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Thêm lựa chọn'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_isEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
