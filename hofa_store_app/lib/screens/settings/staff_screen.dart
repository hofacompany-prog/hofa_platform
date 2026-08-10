import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/staff_member.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../widgets/nav_back_button.dart';

final _staffProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  final merchant = await ref.watch(myMerchantProvider.future);
  if (merchant == null) return [];
  return MerchantRepository().staff(merchant.id);
});

/// Chủ cửa hàng thêm/sửa/xoá nhân viên — tạo tài khoản đăng nhập riêng cho nhân viên ngay
/// (SĐT + mật khẩu chủ tự đặt) và tick chọn quyền được làm (xem STAFF_PERMISSIONS ở
/// server/src/routes/merchants.js, kStaffPermissionLabels ở models/staff_member.dart).
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final merchant = await ref.read(myMerchantProvider.future);
    if (merchant == null || !context.mounted) return;

    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final positionCtrl = TextEditingController();
    final selected = <String>{};
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Thêm nhân viên'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Họ tên',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại (dùng để đăng nhập)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu tạm (từ 6 ký tự)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: positionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chức danh (VD: Thu ngân, Bếp — không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Quyền', style: Theme.of(context).textTheme.titleSmall),
                  ...kStaffPermissionLabels.entries.map(
                    (e) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(e.value),
                      value: selected.contains(e.key),
                      onChanged: (v) => setInner(() {
                        if (v == true) {
                          selected.add(e.key);
                        } else {
                          selected.remove(e.key);
                        }
                      }),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      final password = passwordCtrl.text.trim();
                      if (name.isEmpty || phone.isEmpty || password.length < 6) {
                        setInner(
                          () => error = 'Nhập đủ họ tên, SĐT và mật khẩu (từ 6 ký tự)',
                        );
                        return;
                      }
                      setInner(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await MerchantRepository().createStaff(
                          merchantId: merchant.id,
                          fullName: name,
                          phone: phone,
                          password: password,
                          position: positionCtrl.text.trim(),
                          permissions: selected.toList(),
                        );
                        ref.invalidate(_staffProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setInner(() {
                          saving = false;
                          error = 'Lỗi: $e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tạo tài khoản'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDialog(
    BuildContext context,
    WidgetRef ref,
    StaffMember s,
  ) async {
    final positionCtrl = TextEditingController(text: s.position ?? '');
    final selected = {...s.permissions};
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(s.fullName),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.phone, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: positionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chức danh',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Quyền', style: Theme.of(context).textTheme.titleSmall),
                  ...kStaffPermissionLabels.entries.map(
                    (e) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(e.value),
                      value: selected.contains(e.key),
                      onChanged: (v) => setInner(() {
                        if (v == true) {
                          selected.add(e.key);
                        } else {
                          selected.remove(e.key);
                        }
                      }),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setInner(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await MerchantRepository().updateStaff(
                          s.merchantId,
                          s.id,
                          position: positionCtrl.text.trim(),
                          permissions: selected.toList(),
                        );
                        ref.invalidate(_staffProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setInner(() {
                          saving = false;
                          error = 'Lỗi: $e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StaffMember s,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá nhân viên?'),
        content: Text(
          'Gỡ "${s.fullName}" khỏi cửa hàng? Họ sẽ không đăng nhập được vào app quản lý cửa '
          'hàng nữa, nhưng tài khoản HOFA vẫn còn (giống 1 khách hàng bình thường).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await MerchantRepository().deleteStaff(s.merchantId, s.id);
      ref.invalidate(_staffProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá "${s.fullName}"')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(_staffProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const NavBackButton(),
        title: const Text('Nhân viên'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Thêm nhân viên'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_staffProvider),
        child: staffAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi tải nhân viên: $e')),
          data: (staff) => staff.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    Center(child: Text('Chưa có nhân viên nào — bấm "Thêm nhân viên" bên dưới.')),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: staff.length,
                  itemBuilder: (context, i) {
                    final s = staff[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _editDialog(context, ref, s),
                        title: Text(s.fullName),
                        subtitle: Text(
                          [
                            s.phone,
                            if (s.position != null && s.position!.isNotEmpty) s.position,
                            '${s.permissions.length} quyền',
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Xoá nhân viên',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, ref, s),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
