import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api_exception.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/user_repository.dart';

class CreateStoreScreen extends ConsumerStatefulWidget {
  const CreateStoreScreen({super.key});

  @override
  ConsumerState<CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends ConsumerState<CreateStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _merchantRepo = MerchantRepository();
  final _userRepo = UserRepository();

  final _ownerNameCtrl = TextEditingController();
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
    _ownerNameCtrl.dispose();
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
      // Đảm bảo có hồ sơ public.users trước — trường hợp đăng ký phải xác nhận
      // email rồi mới đăng nhập lại thì auth.syncProfile chưa từng được gọi.
      // Gọi lại vẫn an toàn nếu hồ sơ đã có (cập nhật, không tạo trùng).
      await _userRepo.syncProfile(
        fullName: _ownerNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );

      final slug = '${_slugify(_nameCtrl.text)}-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final merchant = await _merchantRepo.createMerchant(
        name: _nameCtrl.text.trim(),
        slug: slug,
        phone: _phoneCtrl.text.trim(),
      );
      await _merchantRepo.createBranch(
        merchantId: merchant.id,
        name: _branchNameCtrl.text.trim(),
        line1: _line1Ctrl.text.trim(),
        province: _provinceCtrl.text.trim(),
        latitude: double.tryParse(_latCtrl.text.trim()) ?? 0,
        longitude: double.tryParse(_lngCtrl.text.trim()) ?? 0,
        phone: _phoneCtrl.text.trim(),
      );
      ref.invalidate(userProfileProvider);
      ref.invalidate(myMerchantProvider);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
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
        title: const Text('Tạo cửa hàng'),
        actions: [
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('Đăng xuất'),
          ),
        ],
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
                  Text('Vài thông tin để bắt đầu bán hàng trên HOFA',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  Text('Chủ cửa hàng', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ownerNameCtrl,
                    decoration: const InputDecoration(labelText: 'Họ tên'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Cửa hàng', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên cửa hàng'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên cửa hàng' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Số điện thoại liên hệ'),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số điện thoại' : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Chi nhánh chính', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _branchNameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên chi nhánh', hintText: 'VD: Cửa hàng chính'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên chi nhánh' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _line1Ctrl,
                    decoration: const InputDecoration(labelText: 'Địa chỉ (số nhà, đường)'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _provinceCtrl,
                    decoration: const InputDecoration(labelText: 'Tỉnh/Thành phố'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tỉnh/thành' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latCtrl,
                          decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Không hợp lệ' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lngCtrl,
                          decoration: const InputDecoration(labelText: 'Kinh độ (longitude)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Không hợp lệ' : null,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Mẹo: mở Google Maps, bấm giữ vào vị trí cửa hàng để lấy toạ độ.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
