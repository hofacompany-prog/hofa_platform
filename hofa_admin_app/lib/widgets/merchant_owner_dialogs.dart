import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/responsive.dart';
import '../models/user_profile.dart';
import '../providers/admin_providers.dart';
import '../screens/users/users_screen.dart' show roleLabels;

/// Đổi chủ thật cho 1 cửa hàng — dùng chung PATCH /merchants/:id owner_phone/owner_password
/// (xem resolveOwnerIdByPhone trong merchants.js): có mật khẩu = tạo hẳn tài khoản Supabase Auth
/// mới cho SĐT chưa từng có, không có mật khẩu = gắn vào 1 SĐT đã có sẵn hồ sơ (role bất kỳ).
/// Dùng chung ở merchant_detail_screen.dart và user_blocking_records_screen.dart. Trả về true
/// nếu đã đổi thành công — caller tự invalidate provider của màn mình sau đó.
Future<bool> changeMerchantOwnerFlow(
  BuildContext context,
  WidgetRef ref, {
  required String merchantId,
  required String merchantName,
}) async {
  final mode = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('Đổi chủ cửa hàng — $merchantName'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'existing'),
          child: const ListTile(
            leading: Icon(Icons.person_search_outlined),
            title: Text('Chọn user có sẵn'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'new'),
          child: const ListTile(
            leading: Icon(Icons.person_add_alt_outlined),
            title: Text('Tạo tài khoản mới'),
          ),
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return false;

  Map<String, dynamic> payload;
  if (mode == 'existing') {
    final picked = await showDialog<UserProfile>(
      context: context,
      builder: (context) => const _OwnerPickerDialog(),
    );
    if (picked == null) return false;
    payload = {'owner_phone': picked.phone};
  } else {
    if (!context.mounted) return false;
    final entered = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _NewOwnerDialog(),
    );
    if (entered == null) return false;
    payload = {
      'owner_phone': entered['phone'],
      'owner_password': entered['password'],
      'owner_full_name': entered['full_name'],
    };
  }
  if (!context.mounted) return false;

  try {
    await ref.read(adminRepoProvider).updateMerchant(merchantId, payload);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi chủ cửa hàng')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
    return false;
  }
}

/// Chuyển 1 cửa hàng sang đứng tên tài khoản "HOFA Admin" dùng chung (server tự gán
/// GAS_SYNC_OWNER_ID) — cùng chỗ dùng với changeMerchantOwnerFlow. Trả về true nếu thành công.
Future<bool> transferMerchantToAdminOwnerFlow(
  BuildContext context,
  WidgetRef ref, {
  required String merchantId,
  required String merchantName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Chuyển chủ cửa hàng cho Admin?'),
      content: Text(
        '"$merchantName" sẽ chuyển sang đứng tên tài khoản Admin dùng chung — cửa hàng vẫn '
        'hoạt động bình thường, chỉ không còn ai đăng nhập app Cửa hàng quản lý được nữa cho '
        'tới khi gán chủ thật khác.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Chuyển'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    await ref
        .read(adminRepoProvider)
        .transferMerchantToAdminOwner(merchantId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã chuyển chủ cửa hàng cho Admin')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
    return false;
  }
}

/// Tìm + chọn 1 người dùng có sẵn (mọi role — resolveOwnerIdByPhone chấp nhận SĐT của bất kỳ
/// role nào, tự tạo thêm hồ sơ merchant_owner riêng dùng chung auth_user_id) làm chủ mới cho 1
/// cửa hàng. Tap là chọn luôn, không cần nút "Xong" (khác _UserPickerDialog đa chọn ở
/// notifications_screen.dart).
class _OwnerPickerDialog extends ConsumerStatefulWidget {
  const _OwnerPickerDialog();

  @override
  ConsumerState<_OwnerPickerDialog> createState() =>
      _OwnerPickerDialogState();
}

class _OwnerPickerDialogState extends ConsumerState<_OwnerPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<UserProfile>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(adminRepoProvider).users(limit: 500);
      if (mounted) setState(() => _users = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<UserProfile> get _filtered {
    final all = _users ?? const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (u) => u.fullName.toLowerCase().contains(q) || u.phone.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn chủ cửa hàng mới'),
      content: SizedBox(
        width: dialogWidth(context, 480),
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Tìm theo tên hoặc số điện thoại',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text('Lỗi: $_error'))
                  : _users == null
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(child: Text('Không tìm thấy người dùng nào'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final u = _filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            u.fullName.isNotEmpty ? u.fullName : u.phone,
                          ),
                          subtitle: Text(
                            '${u.phone} · ${roleLabels[u.role] ?? u.role}',
                          ),
                          onTap: () => Navigator.pop(context, u),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
      ],
    );
  }
}

/// Nhập SĐT + mật khẩu ban đầu để tạo hẳn 1 tài khoản chủ cửa hàng MỚI (chưa từng có hồ sơ nào
/// dùng SĐT này) — trả về map để changeMerchantOwnerFlow gọi PATCH /merchants/:id với
/// owner_password kèm theo, cho chủ mới tự đăng nhập app Cửa hàng ngay bằng đúng SĐT/mật khẩu này.
class _NewOwnerDialog extends StatefulWidget {
  const _NewOwnerDialog();

  @override
  State<_NewOwnerDialog> createState() => _NewOwnerDialogState();
}

class _NewOwnerDialogState extends State<_NewOwnerDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập đủ họ tên và số điện thoại')),
      );
      return;
    }
    if (_passwordCtrl.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mật khẩu phải từ 6 ký tự')),
      );
      return;
    }
    Navigator.pop(context, {
      'full_name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'password': _passwordCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo tài khoản chủ cửa hàng mới'),
      content: SizedBox(
        width: dialogWidth(context, 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Họ tên'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Số điện thoại'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu (từ 6 ký tự)',
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Tạo & gán')),
      ],
    );
  }
}
