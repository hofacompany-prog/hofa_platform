import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/address.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../address/address_picker_screen.dart';
import '../../widgets/app_version_text.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

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
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ tên')),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Số điện thoại')),
              const SizedBox(height: 12),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addOrEditAddress({Address? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.recipientName);
    final phoneCtrl = TextEditingController(text: existing?.recipientPhone);
    final line1Ctrl = TextEditingController(text: existing?.line1);
    final wardCtrl = TextEditingController(text: existing?.ward);
    final districtCtrl = TextEditingController(text: existing?.district);
    final provinceCtrl = TextEditingController(text: existing?.province);
    double? pickedLat = existing?.latitude;
    double? pickedLng = existing?.longitude;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Thêm địa chỉ' : 'Sửa địa chỉ'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên người nhận')),
                  const SizedBox(height: 12),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'SĐT người nhận')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: Text(pickedLat == null ? 'Chọn vị trí trên bản đồ' : 'Đã chọn vị trí trên bản đồ ✓'),
                    onPressed: () async {
                      final picked = await Navigator.of(context).push<PickedAddress>(
                        MaterialPageRoute(builder: (_) => const AddressPickerScreen()),
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
                  const SizedBox(height: 12),
                  TextField(controller: line1Ctrl, decoration: const InputDecoration(labelText: 'Số nhà, tên đường')),
                  const SizedBox(height: 12),
                  TextField(controller: wardCtrl, decoration: const InputDecoration(labelText: 'Phường/Xã')),
                  const SizedBox(height: 12),
                  TextField(controller: districtCtrl, decoration: const InputDecoration(labelText: 'Quận/Huyện')),
                  const SizedBox(height: 12),
                  TextField(controller: provinceCtrl, decoration: const InputDecoration(labelText: 'Tỉnh/Thành phố')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
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
      'district': districtCtrl.text.trim().isEmpty ? null : districtCtrl.text.trim(),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                            child: Icon(Icons.person, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.fullName, style: theme.textTheme.titleMedium),
                                Text(profile.phone),
                                if (profile.email != null) Text(profile.email!),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _busy ? null : _editProfile),
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
                onPressed: _busy ? null : () => _addOrEditAddress(),
                icon: const Icon(Icons.add),
                label: const Text('Thêm'),
              ),
            ],
          ),
          addressesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Lỗi: $e'),
            data: (addresses) {
              if (addresses.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Chưa có địa chỉ nào'));
              return Column(
                children: addresses
                    .map((a) => Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          child: ListTile(
                            title: Text('${a.recipientName} · ${a.recipientPhone}'),
                            subtitle: Text(a.fullLine),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _addOrEditAddress(existing: a);
                                if (v == 'delete') _deleteAddress(a);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('Sửa')),
                                PopupMenuItem(value: 'delete', child: Text('Xoá')),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
          const SizedBox(height: 12),
          const AppVersionText(),
        ],
      ),
    );
  }
}
