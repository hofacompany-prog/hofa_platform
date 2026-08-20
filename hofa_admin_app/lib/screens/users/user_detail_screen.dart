import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/address.dart';
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import 'users_screen.dart' show roleLabels, statusLabels;
import 'user_devices_card.dart';
import '../../core/responsive.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    bool goBackAfter = false,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(userDetailProvider(widget.userId));
      ref.invalidate(usersProvider);
      ref.invalidate(statsProvider);
      if (goBackAfter && mounted) context.go('/users');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editInfo(UserProfile u) async {
    final nameCtrl = TextEditingController(text: u.fullName);
    final phoneCtrl = TextEditingController(text: u.phone);
    final emailCtrl = TextEditingController(text: u.email ?? '');
    var dob = u.dateOfBirth;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa thông tin người dùng'),
          content: SizedBox(
            width: dialogWidth(context, 360),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dob == null
                            ? 'Ngày sinh: chưa có'
                            : 'Ngày sinh: ${formatDateTime(dob!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: dob ?? DateTime(1990, 1, 1),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setInner(() => dob = picked);
                      },
                      child: const Text('Chọn ngày'),
                    ),
                  ],
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
      ),
    );
    if (ok != true) return;

    await _run(
      () => ref.read(adminRepoProvider).updateUser(u.id, {
        'full_name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        if (dob != null)
          'date_of_birth': dob!.toIso8601String().substring(0, 10),
      }),
    );
  }

  Future<void> _changeRole(UserProfile u) async {
    var selected = u.role;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text('Đổi vai trò — ${u.fullName}'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setInner(() => selected = v ?? selected),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: roleLabels.entries
                  .map(
                    (e) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: e.key,
                      title: Text(e.value),
                    ),
                  )
                  .toList(),
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
      ),
    );
    if (ok != true || selected == u.role) return;
    await _run(
      () =>
          ref.read(adminRepoProvider).setUserRole(u.id, selected).then((_) {}),
    );
  }

  Future<void> _toggleBlock(UserProfile u) async {
    final blocking = u.status == 'active';
    if (blocking) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tạm khoá tài khoản?'),
          content: Text(
            '${u.fullName} sẽ không đăng nhập và đặt hàng được cho tới khi mở lại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tạm khoá'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => ref
          .read(adminRepoProvider)
          .setUserStatus(u.id, blocking ? 'suspended' : 'active')
          .then((_) {}),
    );
  }

  Future<void> _deleteUser(UserProfile u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá vĩnh viễn tài khoản?'),
        content: Text(
          'Xoá triệt để "${u.fullName}" — mất luôn tài khoản đăng nhập, không thể khôi phục. '
          'Nếu tài khoản đang là chủ cửa hàng, có hồ sơ tài xế, hoặc đã từng đặt đơn hàng thì sẽ bị chặn '
          'kèm lý do cụ thể (vì xoá sẽ ảnh hưởng dữ liệu của người khác) — dùng "Tạm khoá" thay vào đó nếu chỉ muốn chặn đăng nhập.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(adminRepoProvider).deleteUser(u.id),
      goBackAfter: true,
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(userDetailProvider(widget.userId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/users'),
        ),
        title: const Text('Chi tiết người dùng'),
        actions: [
          detailAsync.maybeWhen(
            data: (d) => IconButton(
              tooltip: 'Xoá người dùng',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteUser(d.profile),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (detail) {
          final u = detail.profile;
          final blocked = u.status != 'active';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: blocked
                                      ? theme.colorScheme.error.withValues(
                                          alpha: 0.12,
                                        )
                                      : theme.colorScheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                  backgroundImage: u.avatarUrl != null
                                      ? NetworkImage(u.avatarUrl!)
                                      : null,
                                  child: u.avatarUrl == null
                                      ? Icon(
                                          blocked ? Icons.block : Icons.person,
                                          color: blocked
                                              ? theme.colorScheme.error
                                              : theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.fullName,
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Chip(
                                            label: Text(
                                              roleLabels[u.role] ?? u.role,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          const SizedBox(width: 8),
                                          Chip(
                                            label: Text(
                                              statusLabels[u.status] ??
                                                  u.status,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor: blocked
                                                ? theme
                                                      .colorScheme
                                                      .errorContainer
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            _row('Số điện thoại', u.phone),
                            _row('Email', u.email ?? '—'),
                            _row(
                              'Ngày sinh',
                              u.dateOfBirth != null
                                  ? formatDateTime(u.dateOfBirth!)
                                  : '—',
                            ),
                            _row(
                              'SĐT xác minh lúc',
                              u.phoneVerifiedAt != null
                                  ? formatDateTime(u.phoneVerifiedAt!)
                                  : 'Chưa xác minh',
                            ),
                            _row(
                              'Email xác minh lúc',
                              u.emailVerifiedAt != null
                                  ? formatDateTime(u.emailVerifiedAt!)
                                  : 'Chưa xác minh',
                            ),
                            _row(
                              'Đăng nhập gần nhất',
                              u.lastLoginAt != null
                                  ? formatDateTime(u.lastLoginAt!)
                                  : '—',
                            ),
                            _row(
                              'Tạo lúc',
                              u.createdAt != null
                                  ? formatDateTime(u.createdAt!)
                                  : '—',
                            ),
                            _row(
                              'Cập nhật lúc',
                              u.updatedAt != null
                                  ? formatDateTime(u.updatedAt!)
                                  : '—',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _editInfo(u),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Sửa thông tin'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeRole(u),
                                  icon: const Icon(Icons.badge_outlined),
                                  label: const Text('Đổi vai trò'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _toggleBlock(u),
                                  icon: Icon(
                                    blocked
                                        ? Icons.lock_open
                                        : Icons.lock_outline,
                                  ),
                                  label: Text(
                                    blocked
                                        ? 'Mở khoá tài khoản'
                                        : 'Tạm khoá tài khoản',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Địa chỉ đã lưu (${detail.addresses.length})',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if (detail.addresses.isEmpty)
                              const Text('Chưa có địa chỉ nào'),
                            ...detail.addresses.map(
                              (a) => _addressTile(a, theme),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    UserDevicesCard(userId: widget.userId),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _addressTile(Address a, ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${a.label ?? 'Địa chỉ'} · ${a.recipientName} · ${a.recipientPhone}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(a.fullLine, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (a.isDefault)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Chip(
              label: Text('Mặc định'),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    ),
  );
}
