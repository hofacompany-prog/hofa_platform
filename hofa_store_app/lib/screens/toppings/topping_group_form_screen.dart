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

  // Kéo thả đổi thứ tự + bật/tắt lựa chọn CHỈ sửa ở đây, không gọi API ngay — phải bấm "Lưu
  // thay đổi" bên dưới mới thật sự ghi xuống server (khác _submit ở trên, vẫn dành riêng cho
  // tên/bắt buộc/chọn nhiều của cả nhóm). Đổi tên/giá (dialog) và xoá vẫn lưu ngay như cũ, vì
  // bản thân dialog/hộp thoại xác nhận đã là 1 bước "chốt" riêng.
  List<Topping> _localToppings = [];
  bool _toppingsDirty = false;
  bool _savingToppings = false;

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
        _applyToppingsFromServer(g.toppings);
      });
    } catch (e) {
      setState(() => _error = 'Không tải được nhóm topping: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Đồng bộ danh sách lựa chọn mới nhất từ server vào [_localToppings] — nếu đang có thay
  /// đổi thứ tự/bật-tắt CHƯA LƯU (vd vừa thêm 1 lựa chọn mới qua dialog trong lúc còn đang kéo
  /// thả dở), giữ nguyên thứ tự + trạng thái đang chỉnh, chỉ lấy tên/giá mới nhất và thêm/bớt
  /// đúng lựa chọn đã thêm/xoá ở nơi khác — không làm mất thao tác đang dở.
  void _applyToppingsFromServer(List<Topping> serverToppings) {
    if (!_toppingsDirty) {
      _localToppings = List<Topping>.from(serverToppings);
      return;
    }
    final byId = {for (final t in serverToppings) t.id: t};
    final merged = <Topping>[];
    for (final local in _localToppings) {
      final fresh = byId.remove(local.id);
      if (fresh != null) merged.add(fresh.copyWith(isActive: local.isActive));
    }
    merged.addAll(byId.values);
    _localToppings = merged;
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

  /// Chỉ đổi ở local — bấm "Lưu thay đổi" bên dưới mới thật sự ghi xuống server.
  void _toggleToppingActive(Topping t) {
    setState(() {
      final i = _localToppings.indexWhere((x) => x.id == t.id);
      if (i == -1) return;
      _localToppings[i] = _localToppings[i].copyWith(
        isActive: !_localToppings[i].isActive,
      );
      _toppingsDirty = true;
    });
  }

  /// Kéo thả đổi thứ tự hiển thị cho khách — chỉ đổi ở local, không gọi API ngay (khác trước
  /// đây), bấm "Lưu thay đổi" mới ghi sort_order xuống server.
  void _reorderToppings(int oldIndex, int newIndex) {
    setState(() {
      final item = _localToppings.removeAt(oldIndex);
      _localToppings.insert(newIndex, item);
      _toppingsDirty = true;
    });
  }

  /// Ghi lại sort_order/is_active xuống server cho ĐÚNG những lựa chọn thật sự đổi so với dữ
  /// liệu gốc từ server (_group.toppings) — không ghi tràn lan mọi dòng.
  Future<void> _saveToppingChanges() async {
    setState(() => _savingToppings = true);
    try {
      final original = {for (final t in _group?.toppings ?? []) t.id: t};
      for (var i = 0; i < _localToppings.length; i++) {
        final local = _localToppings[i];
        final orig = original[local.id];
        final updates = <String, dynamic>{};
        if (orig == null || orig.sortOrder != i) updates['sort_order'] = i;
        if (orig == null || orig.isActive != local.isActive) {
          updates['is_active'] = local.isActive;
        }
        if (updates.isNotEmpty) {
          await _repo.updateTopping(local.id, updates);
        }
      }
      _toppingsDirty = false;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu thay đổi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingToppings = false);
    }
  }

  void _discardToppingChanges() {
    setState(() {
      _localToppings = List<Topping>.from(_group?.toppings ?? []);
      _toppingsDirty = false;
    });
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
    final toppings = _localToppings;
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
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: toppings.length,
                        onReorderItem: _reorderToppings,
                        itemBuilder: (context, i) {
                          final t = toppings[i];
                          return Card(
                            key: ValueKey('topping-${t.id}'),
                            elevation: 0,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Opacity(
                              opacity: t.isActive ? 1 : 0.5,
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
                                    Switch(
                                      value: t.isActive,
                                      onChanged: (_) => _toggleToppingActive(t),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _toppingDialog(existing: t),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _deleteTopping(t),
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(
                                          Icons.drag_handle,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (_toppingsDirty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Có thay đổi thứ tự/trạng thái chưa lưu',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _savingToppings
                                  ? null
                                  : _discardToppingChanges,
                              child: const Text('Huỷ'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: _savingToppings
                                  ? null
                                  : _saveToppingChanges,
                              child: _savingToppings
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Lưu thay đổi'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
