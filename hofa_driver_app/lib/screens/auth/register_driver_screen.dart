import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api_exception.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/driver_repository.dart';
import '../../widgets/multi_image_upload_field.dart';

/// Hồ sơ tài xế — chỉ hiện khi đã đăng nhập nhưng chưa có bản ghi trong bảng drivers.
class RegisterDriverScreen extends ConsumerStatefulWidget {
  const RegisterDriverScreen({super.key});

  @override
  ConsumerState<RegisterDriverScreen> createState() => _RegisterDriverScreenState();
}

class _RegisterDriverScreenState extends ConsumerState<RegisterDriverScreen> {
  final _repo = DriverRepository();
  final _formKey = GlobalKey<FormState>();
  final _nationalIdCtrl = TextEditingController();
  final _licenseNoCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  String _vehicleType = 'xe máy';
  List<String> _documentUrls = [];

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nationalIdCtrl.dispose();
    _licenseNoCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.register(
        nationalId: _nationalIdCtrl.text.trim(),
        licenseNo: _licenseNoCtrl.text.trim(),
        vehicleType: _vehicleType,
        vehiclePlate: _plateCtrl.text.trim(),
        documentUrls: _documentUrls,
      );
      ref.invalidate(userProfileProvider);
      ref.invalidate(myDriverProvider);
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
        title: const Text('Đăng ký làm tài xế'),
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
                  Text('Vài thông tin để bắt đầu chạy đơn trên HOFA', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nationalIdCtrl,
                    decoration: const InputDecoration(labelText: 'Số CCCD/CMND'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số CCCD/CMND' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _licenseNoCtrl,
                    decoration: const InputDecoration(labelText: 'Số giấy phép lái xe'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số giấy phép lái xe' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _vehicleType,
                    decoration: const InputDecoration(labelText: 'Loại xe'),
                    items: const [
                      DropdownMenuItem(value: 'xe máy', child: Text('Xe máy')),
                      DropdownMenuItem(value: 'xe tải 500kg', child: Text('Xe tải nhỏ (≤500kg)')),
                      DropdownMenuItem(value: 'xe tải 1000kg', child: Text('Xe tải (≤1 tấn)')),
                    ],
                    onChanged: (v) => setState(() => _vehicleType = v ?? _vehicleType),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _plateCtrl,
                    decoration: const InputDecoration(labelText: 'Biển số xe'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập biển số xe' : null,
                  ),
                  const SizedBox(height: 16),
                  MultiImageUploadField(
                    label: 'Ảnh CCCD, giấy phép lái xe, đăng ký xe (không bắt buộc)',
                    folder: 'drivers',
                    initialUrls: _documentUrls,
                    onChanged: (urls) => _documentUrls = urls,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'HOFA sẽ duyệt hồ sơ trước khi bạn bật được chế độ online nhận đơn.',
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
                        : const Text('Hoàn tất đăng ký'),
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
