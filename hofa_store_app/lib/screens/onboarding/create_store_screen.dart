import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api_exception.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../repositories/user_repository.dart';
import '../../widgets/image_upload_field.dart';
import '../location/location_picker_screen.dart';

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

  bool _loading = false;
  String? _error;
  String? _logoUrl;
  double? _pickedLat;
  double? _pickedLng;
  bool _prefilled = false;

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _branchNameCtrl.dispose();
    _line1Ctrl.dispose();
    _provinceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (picked == null) return;
    setState(() {
      _pickedLat = picked.latitude;
      _pickedLng = picked.longitude;
      if (picked.line1.isNotEmpty) _line1Ctrl.text = picked.line1;
      if (picked.province.isNotEmpty) _provinceCtrl.text = picked.province;
    });
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_logoUrl == null) {
      setState(() => _error = 'Vui lòng thêm ảnh cửa hàng');
      return;
    }
    if (_pickedLat == null || _pickedLng == null) {
      setState(() => _error = 'Vui lòng chọn vị trí chi nhánh trên bản đồ');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Lần ghi database ĐẦU TIÊN của cả luồng đăng ký — cố ý để tới đây mới tạo hồ sơ
      // public.users, không tạo sớm hơn lúc xác nhận OTP. Bỏ dở giữa chừng (chưa bấm
      // "Tạo cửa hàng") thì không có thông tin nào bị lưu lại, chỉ có tài khoản đăng
      // nhập (Supabase Auth) tồn tại — bắt buộc phải có để mở được màn hình này.
      await _userRepo.syncProfile(
        fullName: _ownerNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );

      final slug =
          '${_slugify(_nameCtrl.text)}-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final merchant = await _merchantRepo.createMerchant(
        name: _nameCtrl.text.trim(),
        slug: slug,
        phone: _phoneCtrl.text.trim(),
        logoUrl: _logoUrl,
      );
      await _merchantRepo.createBranch(
        merchantId: merchant.id,
        name: _branchNameCtrl.text.trim(),
        line1: _line1Ctrl.text.trim(),
        province: _provinceCtrl.text.trim(),
        latitude: _pickedLat!,
        longitude: _pickedLng!,
        phone: _phoneCtrl.text.trim(),
      );
      ref.read(pendingSignupProvider.notifier).state = null;
      ref.invalidate(userProfileProvider);
      ref.invalidate(myMerchantProvider);
      // Chỉ invalidate provider KHÔNG tự kích hoạt lại redirect của GoRouter (router chỉ
      // tự chạy lại khi có điều hướng hoặc auth state đổi) — phải tự điều hướng sang màn
      // chính, nếu không sẽ đứng yên ở màn "Tạo cửa hàng" dù đã tạo xong.
      if (mounted) context.go('/products');
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
    // Họ tên + SĐT đã nhập lúc đăng ký — chỉ giữ tạm trong bộ nhớ (pendingSignupProvider,
    // KHÔNG lưu database ở bước đó) để điền sẵn ở đây, tránh gõ lại. Chủ cửa hàng vẫn sửa
    // được nếu muốn; dữ liệu chỉ thực sự ghi xuống database khi bấm "Tạo cửa hàng" bên dưới.
    if (!_prefilled) {
      final pending = ref.read(pendingSignupProvider);
      if (pending != null) {
        _prefilled = true;
        _ownerNameCtrl.text = pending.fullName;
        _phoneCtrl.text = pending.phone;
      }
    }

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
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Vài thông tin để bắt đầu bán hàng trên HOFA',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Chủ cửa hàng',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _ownerNameCtrl,
                        decoration: const InputDecoration(labelText: 'Họ tên'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập họ tên'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Cửa hàng',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên cửa hàng',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập tên cửa hàng'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại liên hệ',
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập số điện thoại'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ImageUploadField(
                        label: 'Ảnh cửa hàng (bắt buộc)',
                        folder: 'merchants',
                        onChanged: (url) => setState(() => _logoUrl = url),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Chi nhánh chính',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _branchNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên chi nhánh',
                          hintText: 'VD: Cửa hàng chính',
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
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Đã xác nhận vị trí (${_pickedLat!.toStringAsFixed(5)}, ${_pickedLng!.toStringAsFixed(5)})',
                                style: Theme.of(context).textTheme.bodySmall,
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
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập địa chỉ'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _provinceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tỉnh/Thành phố',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập tỉnh/thành'
                            : null,
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
                      const SizedBox(height: 24),
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
                            : const Text('Tạo cửa hàng'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Che toàn màn hình trong lúc tạo hồ sơ + cửa hàng + chi nhánh (nhiều lệnh gọi
          // API nối tiếp nhau) — báo rõ cho biết đang xử lý, tránh tưởng app bị đứng khi
          // chưa kịp chuyển sang màn chính.
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Đang tạo cửa hàng...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
