import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bank.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/image_upload_field.dart';
import 'location_picker_screen.dart';
import 'merchant_detail_screen.dart' show merchantTypeLabels;

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
  final _ownerFullNameCtrl = TextEditingController();
  final _ownerPasswordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _branchNameCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _bankAccNoCtrl = TextEditingController();
  final _bankAccNameCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _logoUrl;
  String _merchantType = 'regular';
  double? _pickedLat;
  double? _pickedLng;
  String? _pickedWard;
  String? _pickedDistrict;
  bool _obscurePassword = true;
  Bank? _selectedBank;

  @override
  void dispose() {
    _ownerPhoneCtrl.dispose();
    _ownerFullNameCtrl.dispose();
    _ownerPasswordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _branchNameCtrl.dispose();
    _line1Ctrl.dispose();
    _provinceCtrl.dispose();
    _bankAccNoCtrl.dispose();
    _bankAccNameCtrl.dispose();
    super.dispose();
  }

  String _slugify(String name) {
    var s = name.toLowerCase().trim();
    const from =
        'áàảãạăắằẳẵặâấầẩẫậđéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵ';
    const to =
        'aaaaaaaaaaaaaaaaadeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyy';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    return s;
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (picked == null) return;
    setState(() {
      _pickedLat = picked.latitude;
      _pickedLng = picked.longitude;
      _pickedWard = picked.ward;
      _pickedDistrict = picked.district;
      if (picked.line1.isNotEmpty) _line1Ctrl.text = picked.line1;
      if (picked.province.isNotEmpty) _provinceCtrl.text = picked.province;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedLat == null || _pickedLng == null) {
      setState(() => _error = 'Vui lòng chọn vị trí chi nhánh trên bản đồ');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slug =
          '${_slugify(_nameCtrl.text)}-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final merchant = await ref
          .read(adminRepoProvider)
          .createMerchant(
            {
              'name': _nameCtrl.text.trim(),
              'slug': slug,
              'phone': _phoneCtrl.text.trim(),
              'merchant_type': _merchantType,
              if (_logoUrl != null) 'logo_url': _logoUrl,
              if (_selectedBank != null) ...{
                'bank_name': _selectedBank!.name,
                'bank_bin': _selectedBank!.bin,
                'bank_account_no': _bankAccNoCtrl.text.trim(),
                'bank_account_name': _bankAccNameCtrl.text.trim(),
              },
            },
            ownerPhone: _ownerPhoneCtrl.text.trim(),
            ownerPassword: _ownerPasswordCtrl.text.trim(),
            ownerFullName: _ownerFullNameCtrl.text.trim(),
          );
      await ref.read(adminRepoProvider).createBranch(merchant.id, {
        'name': _branchNameCtrl.text.trim(),
        'line1': _line1Ctrl.text.trim(),
        'ward': _pickedWard,
        'district': _pickedDistrict,
        'province': _provinceCtrl.text.trim(),
        'latitude': _pickedLat,
        'longitude': _pickedLng,
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/merchants'),
        ),
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
                  Text('Chủ cửa hàng', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ownerPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SĐT chủ cửa hàng',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập số điện thoại'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerFullNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên chủ cửa hàng',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (_ownerPasswordCtrl.text.trim().isNotEmpty &&
                            (v == null || v.trim().isEmpty))
                        ? 'Nhập họ tên (bắt buộc khi tạo tài khoản mới)'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerPasswordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu ban đầu',
                      helperText:
                          'Để trống nếu SĐT trên đã có tài khoản (gắn cửa hàng vào tài khoản đó). '
                          'Nhập mật khẩu để tạo TÀI KHOẢN HOÀN TOÀN MỚI cho chủ cửa hàng đăng nhập app Cửa hàng.',
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    onChanged: (_) => _formKey.currentState?.validate(),
                    validator: (v) =>
                        (v != null &&
                            v.trim().isNotEmpty &&
                            v.trim().length < 6)
                        ? 'Mật khẩu phải từ 6 ký tự'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  Text('Cửa hàng', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên cửa hàng',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập tên cửa hàng'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _merchantType,
                    decoration: const InputDecoration(
                      labelText: 'Loại cửa hàng',
                      border: OutlineInputBorder(),
                    ),
                    items: merchantTypeLabels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _merchantType = v ?? _merchantType),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại liên hệ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập số điện thoại'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  ImageUploadField(
                    label: 'Ảnh cửa hàng',
                    folder: 'merchants',
                    onChanged: (url) => setState(() => _logoUrl = url),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ngân hàng (không bắt buộc)',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Có thể bổ sung sau ở màn chi tiết cửa hàng — cần điền đủ để cửa hàng rút được tiền.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final banksAsync = ref.watch(banksProvider);
                      return banksAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        ),
                        error: (e, _) =>
                            Text('Không tải được danh sách ngân hàng: $e'),
                        data: (banks) => DropdownButtonFormField<Bank>(
                          initialValue: _selectedBank,
                          decoration: const InputDecoration(
                            labelText: 'Ngân hàng',
                            border: OutlineInputBorder(),
                          ),
                          items: banks
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedBank = v),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankAccNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankAccNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên chủ tài khoản',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Chi nhánh chính', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _branchNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên chi nhánh',
                      hintText: 'VD: Cửa hàng chính',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập tên chi nhánh'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickLocation,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(
                      _pickedLat == null
                          ? 'Chọn vị trí trên bản đồ'
                          : 'Đổi vị trí trên bản đồ',
                    ),
                  ),
                  if (_pickedLat != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Đã xác nhận vị trí (${_pickedLat!.toStringAsFixed(5)}, ${_pickedLng!.toStringAsFixed(5)})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _line1Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ (số nhà, đường)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Nhập địa chỉ' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _provinceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tỉnh/Thành phố',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập tỉnh/thành'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
