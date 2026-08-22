import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/bank.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';
import 'users_screen.dart' show roleLabels;

const _vehicleTypeOptions = [
  ('xe máy', 'Xe máy'),
  ('xe tải 500kg', 'Xe tải nhỏ (≤500kg)'),
  ('xe tải 1000kg', 'Xe tải (≤1 tấn)'),
];

/// Tạo thẳng 1 người dùng mới kèm mật khẩu, đăng nhập được ngay — role='merchant_owner' KHÔNG
/// có ở đây (dùng "Thêm cửa hàng", merchant_form_screen.dart, vì chủ cửa hàng luôn gắn kèm 1
/// cửa hàng). Chọn role khác đổi hẳn bộ field cần điền: merchant_staff cần chọn cửa hàng gắn
/// vào, driver cần đủ giấy tờ xe + tài khoản nhận tiền như tự đăng ký — xem POST /admin/users.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _role = 'customer';
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _dob;

  // Nhân viên cửa hàng
  Merchant? _selectedMerchant;
  final _positionCtrl = TextEditingController();

  // Tài xế
  final _nationalIdCtrl = TextEditingController();
  final _licenseNoCtrl = TextEditingController();
  DateTime? _licenseExpiry;
  var _vehicleType = _vehicleTypeOptions.first.$1;
  final _plateCtrl = TextEditingController();
  final _bankBinCtrl = TextEditingController();
  Bank? _selectedBank;
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _positionCtrl.dispose();
    _nationalIdCtrl.dispose();
    _licenseNoCtrl.dispose();
    _plateCtrl.dispose();
    _bankBinCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Bắt buộc nhập' : null;

  String? _driverRequiredValidator(String? v) =>
      _role == 'driver' ? _requiredValidator(v) : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'merchant_staff' && _selectedMerchant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần chọn cửa hàng cho nhân viên')),
      );
      return;
    }
    if (_role == 'driver' && _selectedBank == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cần chọn ngân hàng nhận tiền')));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(adminRepoProvider).createUser({
        'role': _role,
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passwordCtrl.text,
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (_dob != null)
          'date_of_birth': _dob!.toIso8601String().substring(0, 10),
        if (_role == 'merchant_staff') 'merchant_id': _selectedMerchant!.id,
        if (_role == 'merchant_staff' && _positionCtrl.text.trim().isNotEmpty)
          'position': _positionCtrl.text.trim(),
        if (_role == 'driver') ...{
          'national_id': _nationalIdCtrl.text.trim(),
          'license_no': _licenseNoCtrl.text.trim(),
          if (_licenseExpiry != null)
            'license_expiry': _licenseExpiry!.toIso8601String().substring(
              0,
              10,
            ),
          'vehicle_type': _vehicleType,
          'vehicle_plate': _plateCtrl.text.trim(),
          'bank_name': _selectedBank!.name,
          'bank_bin': _selectedBank!.bin,
          'bank_account_number': _accountNumberCtrl.text.trim(),
          'bank_account_holder': _accountHolderCtrl.text.trim(),
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã tạo người dùng')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creatableRoles = roleLabels.entries
        .where((e) => e.key != 'merchant_owner')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tạo người dùng mới')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò',
                      border: OutlineInputBorder(),
                    ),
                    items: creatableRoles
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      'Muốn tạo chủ cửa hàng? Dùng nút "Thêm cửa hàng" ở mục Cửa hàng — chủ cửa '
                      'hàng luôn gắn kèm 1 cửa hàng, tạo cả 2 cùng lúc.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu ban đầu',
                      border: OutlineInputBorder(),
                      helperText: 'Từ 6 ký tự',
                    ),
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Tối thiểu 6 ký tự' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email (không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dob == null
                              ? 'Ngày sinh: chưa có'
                              : 'Ngày sinh: ${formatDate(_dob!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dob ?? DateTime(1990, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _dob = picked);
                        },
                        child: const Text('Chọn ngày'),
                      ),
                    ],
                  ),

                  if (_role == 'merchant_staff') ...[
                    const Divider(height: 32),
                    Text('Thông tin nhân viên', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Consumer(
                      builder: (context, ref, _) {
                        final merchantsAsync = ref.watch(merchantsProvider);
                        return merchantsAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) =>
                              Text('Không tải được danh sách cửa hàng: $e'),
                          data: (merchants) => DropdownButtonFormField<Merchant>(
                            initialValue: _selectedMerchant,
                            decoration: const InputDecoration(
                              labelText: 'Cửa hàng',
                              border: OutlineInputBorder(),
                            ),
                            items: merchants
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedMerchant = v),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _positionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vị trí (không bắt buộc)',
                        border: OutlineInputBorder(),
                        hintText: 'thu ngân, bếp, quản lý...',
                      ),
                    ),
                  ],

                  if (_role == 'driver') ...[
                    const Divider(height: 32),
                    Text('Thông tin tài xế', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nationalIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số CCCD/CMND',
                        border: OutlineInputBorder(),
                      ),
                      validator: _driverRequiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _licenseNoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số GPLX',
                        border: OutlineInputBorder(),
                      ),
                      validator: _driverRequiredValidator,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _licenseExpiry == null
                                ? 'Hạn GPLX: chưa có'
                                : 'Hạn GPLX: ${formatDate(_licenseExpiry!)}',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _licenseExpiry ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _licenseExpiry = picked);
                            }
                          },
                          child: const Text('Chọn ngày'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Loại xe',
                        border: OutlineInputBorder(),
                      ),
                      items: _vehicleTypeOptions
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.$1,
                              child: Text(v.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _vehicleType = v ?? _vehicleType),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _plateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Biển số xe',
                        border: OutlineInputBorder(),
                      ),
                      validator: _driverRequiredValidator,
                    ),
                    const Divider(height: 28),
                    Text(
                      'Tài khoản nhận tiền',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
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
                          data: (banks) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<Bank>(
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
                                  onChanged: (v) => setState(() {
                                    _selectedBank = v;
                                    _bankBinCtrl.text = v?.bin ?? '';
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  controller: _bankBinCtrl,
                                  readOnly: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Mã BIN',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountNumberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số tài khoản',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: _driverRequiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountHolderCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên chủ tài khoản',
                        border: OutlineInputBorder(),
                      ),
                      validator: _driverRequiredValidator,
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Tạo người dùng'),
                    ),
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
