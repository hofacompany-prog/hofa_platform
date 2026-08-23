import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/pwa_version_service.dart';
import '../../models/address.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../address/address_picker_screen.dart';
import '../../widgets/address_map_flow.dart';
import '../../widgets/app_version_text.dart';
import '../../widgets/permission_settings_section.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;
  bool _checkingUpdate = false;

  /// Chỉ web mới có khái niệm cache PWA cần xoá để lấy bản mới (xem PwaVersionService) — bản
  /// Android cập nhật qua chính Play Store/APK, nút này không có ý nghĩa gì ở đó.
  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final found = await PwaVersionService.checkForUpdate(context);
      if (!found && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn đang dùng phiên bản mới nhất rồi')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _editProfile() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return;
    final nameCtrl = TextEditingController(text: profile.fullName);
    final phoneCtrl = TextEditingController(text: profile.phone);
    final emailCtrl = TextEditingController(text: profile.email ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa hồ sơ'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Họ tên'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(userRepoProvider).updateProfile({
        'full_name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
      });
      ref.invalidate(userProfileProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Thêm địa chỉ MỚI — chọn vị trí trên bản đồ trước, điền tên/SĐT/mô tả sau (xem
  /// widgets/address_map_flow.dart). Sửa địa chỉ có sẵn vẫn dùng form cũ (_addOrEditAddress
  /// bên dưới), vì lúc đó đã có toạ độ rồi, không cần bắt chọn lại bản đồ ngay từ đầu.
  Future<void> _addAddress() async {
    setState(() => _busy = true);
    try {
      await addAddressViaMap(context, ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sửa địa chỉ có sẵn (form nhập tay + nút "Chọn vị trí trên bản đồ" tuỳ chọn để đổi toạ độ).
  Future<void> _addOrEditAddress({Address? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.recipientName);
    final phoneCtrl = TextEditingController(text: existing?.recipientPhone);
    final line1Ctrl = TextEditingController(text: existing?.line1);
    final wardCtrl = TextEditingController(text: existing?.ward);
    final districtCtrl = TextEditingController(text: existing?.district);
    final provinceCtrl = TextEditingController(text: existing?.province);
    double? pickedLat = existing?.latitude;
    double? pickedLng = existing?.longitude;
    String? mapError;
    // Banner tóm tắt hiện NGAY TRONG dialog khi bấm Lưu mà còn thiếu trường bắt buộc — cùng lý
    // do với mapError bên dưới (SnackBar gắn vào màn phía SAU dialog, bị lớp phủ mờ che mất).
    // Đặt ở đầu Column nên luôn thấy ngay không cần cuộn, dialog vẫn mở để nhập tiếp.
    String? formError;

    // Khớp đúng các cột NOT NULL của bảng addresses (hofa-db/01_schema.sql) — ward/district
    // không bắt buộc, giữ nguyên TextField thường, không validator.
    String? requiredValidator(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Bắt buộc nhập' : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Thêm địa chỉ' : 'Sửa địa chỉ'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (formError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên người nhận',
                      ),
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SĐT người nhận',
                      ),
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        pickedLat == null
                            ? 'Chọn vị trí trên bản đồ'
                            : 'Đã chọn vị trí trên bản đồ ✓',
                      ),
                      onPressed: () async {
                        // Bắt nhập tên + SĐT người nhận TRƯỚC khi cho chọn vị trí — tránh khách
                        // chọn xong bản đồ rồi mới phát hiện thiếu, phải quay lại chọn lại từ đầu.
                        // Báo lỗi NGAY TRONG dialog (không dùng SnackBar) — SnackBar gắn vào
                        // ScaffoldMessenger của màn phía SAU dialog, hiện ra bị lớp phủ mờ của
                        // dialog che mất, trông như "ẩn ở dưới".
                        if (nameCtrl.text.trim().isEmpty ||
                            phoneCtrl.text.trim().isEmpty) {
                          setDialogState(
                            () => mapError =
                                'Nhập tên và số điện thoại người nhận trước khi chọn vị trí trên bản đồ',
                          );
                          return;
                        }
                        setDialogState(() => mapError = null);
                        final picked = await Navigator.of(context)
                            .push<PickedAddress>(
                              MaterialPageRoute(
                                builder: (_) => const AddressPickerScreen(),
                              ),
                            );
                        if (picked == null) return;
                        line1Ctrl.text = picked.line1;
                        wardCtrl.text = picked.ward ?? '';
                        districtCtrl.text = picked.district ?? '';
                        provinceCtrl.text = picked.province;
                        setDialogState(() {
                          pickedLat = picked.latitude;
                          pickedLng = picked.longitude;
                        });
                      },
                    ),
                    if (mapError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          mapError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: line1Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Số nhà, tên đường',
                      ),
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: wardCtrl,
                      decoration: const InputDecoration(labelText: 'Phường/Xã'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: districtCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quận/Huyện',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: provinceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tỉnh/Thành phố',
                      ),
                      validator: requiredValidator,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  setDialogState(
                    () => formError =
                        'Còn thiếu thông tin bắt buộc — điền đủ các ô đánh dấu đỏ bên dưới rồi bấm Lưu lại.',
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final data = {
      'recipient_name': nameCtrl.text.trim(),
      'recipient_phone': phoneCtrl.text.trim(),
      'line1': line1Ctrl.text.trim(),
      'ward': wardCtrl.text.trim().isEmpty ? null : wardCtrl.text.trim(),
      'district': districtCtrl.text.trim().isEmpty
          ? null
          : districtCtrl.text.trim(),
      'province': provinceCtrl.text.trim(),
      if (pickedLat != null) 'latitude': pickedLat,
      if (pickedLng != null) 'longitude': pickedLng,
    };

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await ref.read(userRepoProvider).createAddress(data);
      } else {
        await ref.read(userRepoProvider).updateAddress(existing.id, data);
      }
      ref.invalidate(addressesProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAddress(Address a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá địa chỉ này?'),
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

    setState(() => _busy = true);
    try {
      await ref.read(userRepoProvider).deleteAddress(a.id);
      ref.invalidate(addressesProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final addressesAsync = ref.watch(addressesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Lỗi: $e'),
            data: (profile) {
              if (profile == null) return const SizedBox.shrink();
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            child: Icon(
                              Icons.person,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.fullName,
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(profile.phone),
                                if (profile.email != null) Text(profile.email!),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: _busy ? null : _editProfile,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Địa chỉ đã lưu', style: theme.textTheme.titleSmall),
              TextButton.icon(
                onPressed: _busy ? null : _addAddress,
                icon: const Icon(Icons.add),
                label: const Text('Thêm'),
              ),
            ],
          ),
          addressesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Lỗi: $e'),
            data: (addresses) {
              if (addresses.isEmpty)
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Chưa có địa chỉ nào'),
                );
              return Column(
                children: addresses
                    .map(
                      (a) => Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: ListTile(
                          title: Text(
                            '${a.recipientName} · ${a.recipientPhone}',
                          ),
                          subtitle: Text(a.fullLine),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _addOrEditAddress(existing: a);
                              if (v == 'delete') _deleteAddress(a);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Xoá'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const PermissionSettingsSection(),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _checkingUpdate ? null : _checkForUpdate,
              icon: _checkingUpdate
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_outlined),
              label: const Text('Kiểm tra cập nhật'),
            ),
          ],
          const SizedBox(height: 12),
          const AppVersionText(),
        ],
      ),
    );
  }
}
