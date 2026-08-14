import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

const roleLabels = {
  'customer': 'Khách hàng',
  'merchant_owner': 'Chủ cửa hàng',
  'merchant_staff': 'Nhân viên CH',
  'driver': 'Tài xế',
  'admin': 'Quản trị viên',
};

const statusLabels = {
  'pending': 'Chờ kích hoạt',
  'active': 'Đang hoạt động',
  'suspended': 'Tạm khoá',
  'banned': 'Đã cấm',
};

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(usersProvider);
      ref.invalidate(statsProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final roleFilter = ref.watch(userRoleFilterProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Người dùng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(usersProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: roleFilter == null,
                    onSelected: (_) =>
                        ref.read(userRoleFilterProvider.notifier).state = null,
                  ),
                ),
                ...roleLabels.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: roleFilter == e.key,
                      onSelected: (_) =>
                          ref.read(userRoleFilterProvider.notifier).state =
                              e.key,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (users) {
                if (users.isEmpty)
                  return const Center(child: Text('Không có người dùng nào'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: users.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == users.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatCard(
                          label: 'Tổng người dùng (đang lọc)',
                          value: '${users.length}',
                          icon: Icons.people_outline,
                        ),
                      );
                    }
                    final u = users[i];
                    final blocked = u.status != 'active';
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: InkWell(
                        onTap: () => context.push('/users/${u.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: blocked
                                        ? theme.colorScheme.error.withValues(
                                            alpha: 0.12,
                                          )
                                        : theme.colorScheme.primary.withValues(
                                            alpha: 0.12,
                                          ),
                                    child: Icon(
                                      blocked ? Icons.block : Icons.person,
                                      color: blocked
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${u.phone}${u.email != null ? ' · ${u.email}' : ''}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Chip(
                                    label: Text(roleLabels[u.role] ?? u.role),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Chip(
                                    label: Text(
                                      statusLabels[u.status] ?? u.status,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: blocked
                                        ? theme.colorScheme.errorContainer
                                        : null,
                                  ),
                                  PopupMenuButton<String>(
                                    enabled: !_busy,
                                    onSelected: (v) {
                                      if (v == 'role') _changeRole(u);
                                      if (v == 'block') _toggleBlock(u);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'role',
                                        child: Text('Đổi vai trò'),
                                      ),
                                      PopupMenuItem(
                                        value: 'block',
                                        child: Text(
                                          blocked
                                              ? 'Mở khoá tài khoản'
                                              : 'Tạm khoá tài khoản',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
