import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/product_repository.dart';

/// groupId == null: tạo nhóm topping mới (thư viện dùng chung của cửa hàng, gắn được vào
/// nhiều sản phẩm — xem product_form_screen.dart). Có id: sửa nhóm + quản lý danh sách
/// lựa chọn (toppings) bên trong nhóm đó.
class ToppingGroupFormScreen extends ConsumerStatefulWidget {
  final String? groupId;
  const ToppingGroupFormScreen({super.key, this.groupId});

  @override
  ConsumerState<ToppingGroupFormScreen> createState() =>
      _ToppingGroupFormScreenState();
}

class _ToppingGroupFormScreenState
    extends ConsumerState<ToppingGroupFormScreen> {
  final _repo = ProductRepository();
  final _nameCtrl = TextEditingController();
  bool _isRequired = false;
  bool _allowMultiple = false;
  ToppingGroup? _group;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.groupId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final g = await _repo.toppingGroup(widget.groupId!);
      setState(() {
        _group = g;
        _nameCtrl.text = g.name;
        _isRequired = g.isRequired;
        _allowMultiple = g.allowMultiple;
      });
    } catch (e) {
      setState(() => _error = 'Không tải được nhóm topping: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên nhóm');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await _repo.updateToppingGroup(widget.groupId!, {
          'name': name,
          'is_required': _isRequired,
          'allow_multiple': _allowMultiple,
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
        final created = await _repo.createToppingGroup(
          merchantId: merchant.id,
          name: name,
          isRequired: _isRequired,
          allowMultiple: _allowMultiple,
        );
        if (mounted) {
          context.pushReplacement('/topping-groups/${created.id}/edit');
        }
      }
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toppingDialog({Topping? existing}) async {
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

    try {
      if (existing == null) {
        await _repo.createTopping(
          groupId: widget.groupId!,
          name: nameCtrl.text.trim(),
          price: price,
        );
      } else {
        await _repo.updateTopping(existing.id, {
          'name': nameCtrl.text.trim(),
          'price': price,
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

  Future<void> _deleteTopping(Topping t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá lựa chọn?'),
        content: Text('Xoá "${t.name}" khỏi nhóm topping này?'),
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
      await _repo.deleteTopping(t.id);
      await _load();
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
    final toppings = _group?.toppings ?? const <Topping>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa nhóm topping' : 'Thêm nhóm topping'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: !_isEdit,
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
                    value: _isRequired,
                    onChanged: (v) => setState(() => _isRequired = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho chọn nhiều mục'),
                    subtitle: const Text(
                      'Bật: chọn nhiều · Tắt: chỉ chọn 1 trong nhóm',
                    ),
                    value: _allowMultiple,
                    onChanged: (v) => setState(() => _allowMultiple = v),
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
                        : Text(_isEdit ? 'Lưu' : 'Tạo nhóm'),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lựa chọn trong nhóm',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        TextButton.icon(
                          onPressed: () => _toppingDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm lựa chọn'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (toppings.isEmpty)
                      const Text('Chưa có lựa chọn nào trong nhóm này.')
                    else
                      ...toppings.map(
                        (t) => Card(
                          elevation: 0,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
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
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _toppingDialog(existing: t),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteTopping(t),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
