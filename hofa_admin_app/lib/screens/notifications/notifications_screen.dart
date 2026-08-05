import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/admin_notification.dart';
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

/// Gửi thông báo đẩy (push notification) cho khách hàng — qua Firebase Cloud Messaging
/// (xem server/src/push.js). 2 chế độ: "Tất cả khách hàng" (mọi thiết bị đã đăng ký nhận
/// thông báo) hoặc "Khách hàng cụ thể" (admin tự chọn 1 hoặc nhiều khách từ danh sách).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  bool _sendToAll = true;
  final List<UserProfile> _selectedUsers = [];
  int? _specificAudienceCount;
  bool _loadingSpecificAudience = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshSpecificAudienceCount() async {
    if (_selectedUsers.isEmpty) {
      setState(() => _specificAudienceCount = 0);
      return;
    }
    setState(() => _loadingSpecificAudience = true);
    try {
      final count = await ref
          .read(adminRepoProvider)
          .notificationAudienceCount(
            userIds: _selectedUsers.map((u) => u.id).toList(),
          );
      if (mounted) setState(() => _specificAudienceCount = count);
    } finally {
      if (mounted) setState(() => _loadingSpecificAudience = false);
    }
  }

  Future<void> _pickUsers() async {
    final result = await showDialog<List<UserProfile>>(
      context: context,
      builder: (context) =>
          _UserPickerDialog(initiallySelected: _selectedUsers),
    );
    if (result == null) return;
    setState(() {
      _selectedUsers
        ..clear()
        ..addAll(result);
    });
    await _refreshSpecificAudienceCount();
  }

  Future<void> _send(int allAudienceCount) async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) {
      _showError('Vui lòng nhập tiêu đề');
      return;
    }
    if (body.isEmpty) {
      _showError('Vui lòng nhập nội dung');
      return;
    }
    if (!_sendToAll && _selectedUsers.isEmpty) {
      _showError('Vui lòng chọn ít nhất 1 khách hàng');
      return;
    }

    final audienceCount = _sendToAll
        ? allAudienceCount
        : (_specificAudienceCount ?? 0);
    final audienceLabel = _sendToAll
        ? 'khoảng $audienceCount thiết bị của toàn bộ khách hàng'
        : '${_selectedUsers.length} khách hàng đã chọn (khoảng $audienceCount thiết bị)';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi thông báo?'),
        content: Text(
          'Thông báo sẽ được gửi ngay tới $audienceLabel. Không thể thu hồi sau khi đã gửi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(adminRepoProvider)
          .sendNotification(
            title: title,
            body: body,
            userIds: _sendToAll
                ? null
                : _selectedUsers.map((u) => u.id).toList(),
          );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _selectedUsers.clear();
        _specificAudienceCount = null;
      });
      ref.invalidate(notificationsProvider);
      ref.invalidate(notificationAudienceCountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã gửi tới ${result.sentCount}/${result.totalCount} thiết bị',
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audienceAsync = ref.watch(notificationAudienceCountProvider);
    final historyAsync = ref.watch(notificationsProvider);
    final allAudienceCount = audienceAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gửi thông báo đẩy tới ứng dụng khách hàng — hiện ra ngay trên điện '
                    'thoại của khách kể cả khi không mở app. Gửi cho toàn bộ khách hàng '
                    'hoặc chọn riêng 1 nhóm khách cụ thể.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đối tượng nhận',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          RadioGroup<bool>(
                            groupValue: _sendToAll,
                            onChanged: (v) {
                              if (!_sending && v != null) {
                                setState(() => _sendToAll = v);
                              }
                            },
                            child: const Column(
                              children: [
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text('Tất cả khách hàng'),
                                  value: true,
                                ),
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text('Khách hàng cụ thể'),
                                  value: false,
                                ),
                              ],
                            ),
                          ),
                          if (!_sendToAll) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _sending ? null : _pickUsers,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: Text(
                                    _selectedUsers.isEmpty
                                        ? 'Chọn khách hàng'
                                        : 'Sửa danh sách (${_selectedUsers.length})',
                                  ),
                                ),
                                ..._selectedUsers.map(
                                  (u) => Chip(
                                    label: Text(
                                      u.fullName.isNotEmpty
                                          ? u.fullName
                                          : u.phone,
                                    ),
                                    onDeleted: _sending
                                        ? null
                                        : () {
                                            setState(
                                              () => _selectedUsers.remove(u),
                                            );
                                            _refreshSpecificAudienceCount();
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 280,
                    child: StatCard(
                      label: 'Sẽ gửi tới',
                      value: _sendToAll
                          ? (audienceAsync.isLoading
                                ? '...'
                                : '$allAudienceCount thiết bị')
                          : (_loadingSpecificAudience
                                ? '...'
                                : '${_specificAudienceCount ?? 0} thiết bị'),
                      sub: _sendToAll
                          ? 'Toàn bộ khách hàng đã bật thông báo'
                          : '${_selectedUsers.length} khách hàng đã chọn',
                      icon: Icons.smartphone_outlined,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Soạn thông báo mới',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _titleCtrl,
                            enabled: !_sending,
                            maxLength: 150,
                            decoration: const InputDecoration(
                              labelText: 'Tiêu đề',
                              helperText: 'Ngắn gọn, hiện đậm ở đầu thông báo',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _bodyCtrl,
                            enabled: !_sending,
                            maxLength: 500,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Nội dung',
                              helperText: 'Nội dung đầy đủ của thông báo',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _sending
                                  ? null
                                  : () => _send(allAudienceCount),
                              icon: _sending
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined),
                              label: const Text('Gửi thông báo'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Lịch sử đã gửi', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  historyAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Lỗi: $e'),
                    data: (items) => items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'Chưa gửi thông báo nào.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          )
                        : Column(
                            children: items
                                .map((n) => _NotificationCard(notification: n))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserPickerDialog extends ConsumerStatefulWidget {
  final List<UserProfile> initiallySelected;
  const _UserPickerDialog({required this.initiallySelected});

  @override
  ConsumerState<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends ConsumerState<_UserPickerDialog> {
  final _searchCtrl = TextEditingController();
  late final Map<String, UserProfile> _selected;
  List<UserProfile>? _customers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = {for (final u in widget.initiallySelected) u.id: u};
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(adminRepoProvider)
          .users(role: 'customer', limit: 500);
      if (mounted) setState(() => _customers = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<UserProfile> get _filtered {
    final all = _customers ?? const [];
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
      title: const Text('Chọn khách hàng'),
      content: SizedBox(
        width: 480,
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
                  : _customers == null
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(child: Text('Không tìm thấy khách hàng nào'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final u = _filtered[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.containsKey(u.id),
                          title: Text(
                            u.fullName.isNotEmpty ? u.fullName : u.phone,
                          ),
                          subtitle: Text(u.phone),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected[u.id] = u;
                            } else {
                              _selected.remove(u.id);
                            }
                          }),
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
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.values.toList()),
          child: Text('Xong (${_selected.length})'),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AdminNotification notification;
  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSpecific = notification.target == 'specific_users';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(notification.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    isSpecific
                        ? '${notification.sentCount}/${notification.totalCount} thiết bị · ${notification.recipientNames.length} khách chọn riêng'
                        : '${notification.sentCount}/${notification.totalCount} thiết bị · Tất cả khách hàng',
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(formatDateTime(notification.createdAt)),
                ),
                if (notification.createdByName != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Gửi bởi ${notification.createdByName}'),
                  ),
              ],
            ),
            if (isSpecific && notification.recipientNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Gửi cho: ${notification.recipientNames.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
