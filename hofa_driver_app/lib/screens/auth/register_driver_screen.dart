import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api_exception.dart';
import '../../models/bank.dart';
import '../../models/driver.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/driver_repository.dart';
import '../../widgets/multi_image_upload_field.dart';

/// Hồ sơ tài xế — dùng cho cả 2 luồng: (1) đăng ký lần đầu, [existing] null, chưa có bản ghi
/// trong bảng drivers; (2) sửa/nộp lại hồ sơ sau khi bị admin từ chối, [existing] là hồ sơ hiện
/// tại (điền sẵn), gọi PATCH /drivers/me thay vì POST /drivers/register — server tự xoá
/// rejected_at khi gọi thành công, đưa hồ sơ về lại "đang chờ xét duyệt".
class RegisterDriverScreen extends ConsumerStatefulWidget {
  final Driver? existing;
  const RegisterDriverScreen({super.key, this.existing});

  @override
  ConsumerState<RegisterDriverScreen> createState() => _RegisterDriverScreenState();
}

class _RegisterDriverScreenState extends ConsumerState<RegisterDriverScreen> {
  final _repo = DriverRepository();
  final _formKey = GlobalKey<FormState>();
  final _nationalIdCtrl = TextEditingController();
  final _licenseNoCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  String _vehicleType = 'xe máy';
  Bank? _selectedBank;
  bool _bankPrefillAttempted = false;
  List<String> _documentUrls = [];

  bool _loading = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nationalIdCtrl.text = existing.nationalId ?? '';
      _licenseNoCtrl.text = existing.licenseNo ?? '';
      _plateCtrl.text = existing.vehiclePlate ?? '';
      _accountNumberCtrl.text = existing.bankAccountNumber ?? '';
      _accountHolderCtrl.text = existing.bankAccountHolder ?? '';
      _vehicleType = existing.vehicleType ?? _vehicleType;
      _documentUrls = existing.documentUrls;
    }
  }

  @override
  void dispose() {
    _nationalIdCtrl.dispose();
    _licenseNoCtrl.dispose();
    _plateCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBank == null) {
      setState(() => _error = 'Chọn ngân hàng nhận tiền');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isEditing) {
        await _repo.updateProfile(
          nationalId: _nationalIdCtrl.text.trim(),
          licenseNo: _licenseNoCtrl.text.trim(),
          vehicleType: _vehicleType,
          vehiclePlate: _plateCtrl.text.trim(),
          bankName: _selectedBank!.name,
          bankBin: _selectedBank!.bin,
          bankAccountNumber: _accountNumberCtrl.text.trim(),
          bankAccountHolder: _accountHolderCtrl.text.trim(),
          documentUrls: _documentUrls,
        );
      } else {
        await _repo.register(
          nationalId: _nationalIdCtrl.text.trim(),
          licenseNo: _licenseNoCtrl.text.trim(),
          vehicleType: _vehicleType,
          vehiclePlate: _plateCtrl.text.trim(),
          bankName: _selectedBank!.name,
          bankBin: _selectedBank!.bin,
          bankAccountNumber: _accountNumberCtrl.text.trim(),
          bankAccountHolder: _accountHolderCtrl.text.trim(),
          documentUrls: _documentUrls,
        );
      }
      ref.invalidate(userProfileProvider);
      ref.invalidate(myDriverProvider);
      if (_isEditing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã nộp lại hồ sơ — chờ HOFA xét duyệt tiếp nhé!')),
        );
        context.pop();
      }
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
    final banksAsync = ref.watch(banksProvider);
    if (_isEditing && !_bankPrefillAttempted) {
      final banks = banksAsync.valueOrNull;
      if (banks != null) {
        _bankPrefillAttempted = true;
        final bin = widget.existing!.bankBin;
        if (bin != null && bin.isNotEmpty) {
          final match = banks.where((b) => b.bin == bin);
          if (match.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedBank = match.first);
            });
          }
        }
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Sửa hồ sơ tài xế' : 'Đăng ký làm tài xế'),
        actions: _isEditing
            ? null
            : [
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
                  Text(
                    _isEditing
                        ? 'Sửa lại thông tin bị từ chối rồi nộp lại để HOFA xét duyệt tiếp'
                        : 'Vài thông tin để bắt đầu chạy đơn trên HOFA',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_isEditing && widget.existing?.rejectionReason != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Lý do bị từ chối: ${widget.existing!.rejectionReason}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
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
                  const SizedBox(height: 20),
                  Text('Tài khoản nhận tiền', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Dùng để HOFA chuyển tiền khi bạn rút ví.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  banksAsync.when(
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
                    error: (e, _) => Text('Không tải được danh sách ngân hàng: $e'),
                    data: (banks) => DropdownButtonFormField<Bank>(
                      initialValue: _selectedBank,
                      decoration: const InputDecoration(labelText: 'Ngân hàng'),
                      items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
                      onChanged: (v) => setState(() => _selectedBank = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNumberCtrl,
                    decoration: const InputDecoration(labelText: 'Số tài khoản'),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số tài khoản' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountHolderCtrl,
                    decoration: const InputDecoration(labelText: 'Tên chủ tài khoản'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên chủ tài khoản' : null,
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
                        : Text(_isEditing ? 'Cập nhật hồ sơ' : 'Hoàn tất đăng ký'),
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
