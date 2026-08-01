import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_providers.dart';

/// Admin tạo hộ 1 cửa hàng cho chủ đã có tài khoản (tìm theo SĐT) — cửa hàng tạo ra
/// ở trạng thái draft như bình thường, admin tự duyệt sau ở màn hình chi tiết.
class MerchantFormScreen extends ConsumerStatefulWidget {
  const MerchantFormScreen({super.key});

  @override
  ConsumerState<MerchantFormScreen> createState() => _MerchantFormScreenState();
}

class _MerchantFormScreenState extends ConsumerState<MerchantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerPhoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _branchNameCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ownerPhoneCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _branchNameCtrl.dispose();
    _line1Ctrl.dispose();
    _provinceCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  String _slugify(String name) {
    var s = name.toLowerCase().trim();
    const from = 'áàảãạăắằẳẵặâấầẩẫậđéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵ';
    const to = 'aaaaaaaaaaaaaaaaadeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyy';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '').replaceAll(RegExp(r'\s+'), '-');
    return s;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slug = '${_slugify(_nameCtrl.text)}-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final merchant = await ref.read(adminRepoProvider).createMerchant(
        {
          'name': _nameCtrl.text.trim(),
          'slug': slug,
          'phone': _phoneCtrl.text.trim(),
        },
        ownerPhone: _ownerPhoneCtrl.text.trim(),
      );
      await ref.read(adminRepoProvider).createBranch(merchant.id, {
        'name': _branchNameCtrl.text.trim(),
        'line1': _line1Ctrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'latitude': double.tryParse(_latCtrl.text.trim()) ?? 0,
        'longitude': double.tryParse(_lngCtrl.text.trim()) ?? 0,
        'is_main': true,
        'phone': _phoneCtrl.text.trim(),
      });
      ref.invalidate(merchantsProvider);
      ref.invalidate(statsProvider);
      if (mounted) context.go('/merchants/${merchant.id}');
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/merchants')),
        title: const Text('Tạo cửa hàng'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Chủ cửa hàng', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ownerPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SĐT chủ cửa hàng (tài khoản đã có sẵn)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số điện thoại' : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Cửa hàng', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên cửa hàng', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên cửa hàng' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Số điện thoại liên hệ', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số điện thoại' : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Chi nhánh chính', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _branchNameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Tên chi nhánh', hintText: 'VD: Cửa hàng chính', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên chi nhánh' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _line1Ctrl,
                    decoration: const InputDecoration(labelText: 'Địa chỉ (số nhà, đường)', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _provinceCtrl,
                    decoration: const InputDecoration(labelText: 'Tỉnh/Thành phố', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tỉnh/thành' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latCtrl,
                          decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)', border: OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Không hợp lệ' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lngCtrl,
                          decoration: const InputDecoration(labelText: 'Kinh độ (longitude)', border: OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Không hợp lệ' : null,
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Tạo cửa hàng'),
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
