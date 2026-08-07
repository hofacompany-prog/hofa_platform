import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/admin_notification.dart';
import '../../models/merchant.dart';
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

const _userPickerRoleLabels = {'customer': 'khách hàng', 'driver': 'tài xế'};

/// Gửi thông báo đẩy (push notification) — qua Firebase Cloud Messaging (xem
/// server/src/push.js). Chọn theo 2 bước: (1) nhóm đối tượng — Khách hàng / Cửa hàng /
/// Tài xế, (2) trong nhóm đó gửi cho "Tất cả" hay tự chọn 1 hoặc nhiều đối tượng cụ thể.
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

  String _audienceType = 'customer';
  bool _sendToAll = true;
  bool _showBadge = false;
  String? _targetScreen;
  final List<UserProfile> _selectedUsers = [];
  final List<Merchant> _selectedMerchants = [];

  int? _allAudienceCount;
  bool _loadingAllAudience = false;
  int? _specificAudienceCount;
  bool _loadingSpecificAudience = false;

  @override
  void initState() {
    super.initState();
    _loadAllAudienceCount();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllAudienceCount() async {
    setState(() => _loadingAllAudience = true);
    try {
      final count = await ref
          .read(adminRepoProvider)
          .notificationAudienceCount(audienceType: _audienceType);
      if (mounted) setState(() => _allAudienceCount = count);
    } finally {
      if (mounted) setState(() => _loadingAllAudience = false);
    }
  }

  Future<void> _refreshSpecificAudienceCount() async {
    final hasSelection = _audienceType == 'merchant'
        ? _selectedMerchants.isNotEmpty
        : _selectedUsers.isNotEmpty;
    if (!hasSelection) {
      setState(() => _specificAudienceCount = 0);
      return;
    }
    setState(() => _loadingSpecificAudience = true);
    try {
      final count = await ref
          .read(adminRepoProvider)
          .notificationAudienceCount(
            audienceType: _audienceType,
            userIds: _audienceType == 'merchant'
                ? null
                : _selectedUsers.map((u) => u.id).toList(),
            merchantIds: _audienceType == 'merchant'
                ? _selectedMerchants.map((m) => m.id).toList()
                : null,
          );
      if (mounted) setState(() => _specificAudienceCount = count);
    } finally {
      if (mounted) setState(() => _loadingSpecificAudience = false);
    }
  }

  void _onAudienceTypeChanged(String type) {
    if (type == _audienceType || _sending) return;
    setState(() {
      _audienceType = type;
      _selectedUsers.clear();
      _selectedMerchants.clear();
      _allAudienceCount = null;
      _specificAudienceCount = null;
      _targetScreen = null;
    });
    if (_sendToAll) {
      _loadAllAudienceCount();
    } else {
      _refreshSpecificAudienceCount();
    }
  }

  void _onSendToAllChanged(bool value) {
    if (value == _sendToAll || _sending) return;
    setState(() => _sendToAll = value);
    if (value) {
      if (_allAudienceCount == null) _loadAllAudienceCount();
    } else {
      _refreshSpecificAudienceCount();
    }
  }

  Future<void> _pickEntities() async {
    if (_audienceType == 'merchant') {
      final result = await showDialog<List<Merchant>>(
        context: context,
        builder: (context) =>
            _MerchantPickerDialog(initiallySelected: _selectedMerchants),
      );
      if (result == null) return;
      setState(() {
        _selectedMerchants
          ..clear()
          ..addAll(result);
      });
    } else {
      final result = await showDialog<List<UserProfile>>(
        context: context,
        builder: (context) => _UserPickerDialog(
          role: _audienceType,
          initiallySelected: _selectedUsers,
        ),
      );
      if (result == null) return;
      setState(() {
        _selectedUsers
          ..clear()
          ..addAll(result);
      });
    }
    await _refreshSpecificAudienceCount();
  }

  Future<void> _send() async {
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
    final selectionCount = _audienceType == 'merchant'
        ? _selectedMerchants.length
        : _selectedUsers.length;
    if (!_sendToAll && selectionCount == 0) {
      _showError(
        'Vui lòng chọn ít nhất 1 ${_userPickerRoleLabels[_audienceType] ?? 'cửa hàng'}',
      );
      return;
    }

    final audienceCount = _sendToAll
        ? (_allAudienceCount ?? 0)
        : (_specificAudienceCount ?? 0);
    final typeLabel = audienceTypeLabels[_audienceType]!.toLowerCase();
    final audienceLabel = _sendToAll
        ? 'khoảng $audienceCount thiết bị của toàn bộ $typeLabel'
        : '$selectionCount $typeLabel đã chọn (khoảng $audienceCount thiết bị)';

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
            audienceType: _audienceType,
            userIds: (!_sendToAll && _audienceType != 'merchant')
                ? _selectedUsers.map((u) => u.id).toList()
                : null,
            merchantIds: (!_sendToAll && _audienceType == 'merchant')
                ? _selectedMerchants.map((m) => m.id).toList()
                : null,
            showBadge: _showBadge,
            targetScreen: _targetScreen,
          );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _selectedUsers.clear();
        _selectedMerchants.clear();
        _specificAudienceCount = null;
        _showBadge = false;
        _targetScreen = null;
      });
      ref.invalidate(notificationsProvider);
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
    final historyAsync = ref.watch(notificationsProvider);
    final typeLabel = audienceTypeLabels[_audienceType]!;
    final typeLabelLower = typeLabel.toLowerCase();
    final selectionCount = _audienceType == 'merchant'
        ? _selectedMerchants.length
        : _selectedUsers.length;

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
                    'Gửi thông báo đẩy — hiện ra ngay trên điện thoại của người nhận kể '
                    'cả khi không mở app. Chọn nhóm (khách hàng/cửa hàng/tài xế) rồi gửi '
                    'cho cả nhóm hoặc tự chọn 1/nhiều đối tượng cụ thể.',
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
                            'Nhóm đối tượng',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: audienceTypeLabels.entries
                                .map(
                                  (e) => ChoiceChip(
                                    label: Text(e.value),
                                    selected: _audienceType == e.key,
                                    onSelected: _sending
                                        ? null
                                        : (_) => _onAudienceTypeChanged(e.key),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Đối tượng nhận',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          RadioGroup<bool>(
                            groupValue: _sendToAll,
                            onChanged: (v) {
                              if (v != null) _onSendToAllChanged(v);
                            },
                            child: Column(
                              children: [
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text('Tất cả $typeLabelLower'),
                                  value: true,
                                ),
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text('$typeLabel cụ thể'),
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
                                  onPressed: _sending ? null : _pickEntities,
                                  icon: const Icon(Icons.add_circle_outline),
                                  label: Text(
                                    selectionCount == 0
                                        ? 'Chọn $typeLabelLower'
                                        : 'Sửa danh sách ($selectionCount)',
                                  ),
                                ),
                                if (_audienceType == 'merchant')
                                  ..._selectedMerchants.map(
                                    (m) => Chip(
                                      label: Text(m.name),
                                      onDeleted: _sending
                                          ? null
                                          : () {
                                              setState(
                                                () => _selectedMerchants.remove(
                                                  m,
                                                ),
                                              );
                                              _refreshSpecificAudienceCount();
                                            },
                                    ),
                                  )
                                else
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
                          ? (_loadingAllAudience
                                ? '...'
                                : '${_allAudienceCount ?? 0} thiết bị')
                          : (_loadingSpecificAudience
                                ? '...'
                                : '${_specificAudienceCount ?? 0} thiết bị'),
                      sub: _sendToAll
                          ? 'Toàn bộ $typeLabelLower đã bật thông báo'
                          : '$selectionCount $typeLabelLower đã chọn',
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
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _showBadge,
                            onChanged: _sending
                                ? null
                                : (v) => setState(() => _showBadge = v ?? false),
                            title: const Text(
                              'Hiển thị số trên biểu tượng ứng dụng',
                            ),
                            subtitle: const Text(
                              'Cộng thêm 1 vào ô số nhỏ trên icon PWA ở màn hình chính của '
                              'người nhận (chỉ áp dụng nếu họ đã "Thêm vào màn hình chính"). '
                              'Thông báo về đơn hàng luôn tự hiện số, không cần bật ở đây.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String?>(
                            initialValue: _targetScreen,
                            decoration: const InputDecoration(
                              labelText: 'Khi bấm vào thông báo, mở màn nào',
                              helperText:
                                  'Để trống thì bấm vào chỉ mở app ở màn mặc định, không nhảy tới đâu cụ thể.',
                              helperMaxLines: 2,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Không chỉ định'),
                              ),
                              ...(notificationTargetScreensByAudience[_audienceType] ??
                                      const {})
                                  .entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  ),
                            ],
                            onChanged: _sending
                                ? null
                                : (v) => setState(() => _targetScreen = v),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _sending ? null : _send,
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
  final String role;
  final List<UserProfile> initiallySelected;
  const _UserPickerDialog({
    required this.role,
    required this.initiallySelected,
  });

  @override
  ConsumerState<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends ConsumerState<_UserPickerDialog> {
  final _searchCtrl = TextEditingController();
  late final Map<String, UserProfile> _selected;
  List<UserProfile>? _users;
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
          .users(role: widget.role, limit: 500);
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
    final roleLabel = _userPickerRoleLabels[widget.role] ?? widget.role;
    return AlertDialog(
      title: Text(
        'Chọn ${roleLabel[0].toUpperCase()}${roleLabel.substring(1)}',
      ),
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
                  : _users == null
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? Center(child: Text('Không tìm thấy $roleLabel nào'))
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

class _MerchantPickerDialog extends ConsumerStatefulWidget {
  final List<Merchant> initiallySelected;
  const _MerchantPickerDialog({required this.initiallySelected});

  @override
  ConsumerState<_MerchantPickerDialog> createState() =>
      _MerchantPickerDialogState();
}

class _MerchantPickerDialogState extends ConsumerState<_MerchantPickerDialog> {
  final _searchCtrl = TextEditingController();
  late final Map<String, Merchant> _selected;
  List<Merchant>? _merchants;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = {for (final m in widget.initiallySelected) m.id: m};
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(adminRepoProvider).merchants(limit: 500);
      if (mounted) setState(() => _merchants = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<Merchant> get _filtered {
    final all = _merchants ?? const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn cửa hàng'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Tìm theo tên cửa hàng',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text('Lỗi: $_error'))
                  : _merchants == null
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(child: Text('Không tìm thấy cửa hàng nào'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final m = _filtered[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.containsKey(m.id),
                          title: Text(m.name),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected[m.id] = m;
                            } else {
                              _selected.remove(m.id);
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
    final isSpecific = notification.target == 'specific';
    final typeLabel =
        audienceTypeLabels[notification.audienceType] ??
        notification.audienceType;
    final names = notification.audienceType == 'merchant'
        ? notification.targetMerchantNames
        : notification.recipientNames;
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
                        ? '${notification.sentCount}/${notification.totalCount} thiết bị · $typeLabel (${names.length})'
                        : '${notification.sentCount}/${notification.totalCount} thiết bị · Tất cả ${typeLabel.toLowerCase()}',
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(formatDateTime(notification.createdAt)),
                ),
                if (notification.showBadge)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Có badge'),
                  ),
                if (notification.targetScreen != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.open_in_new, size: 14),
                    label: Text(
                      notificationTargetScreensByAudience[notification.audienceType]?[notification.targetScreen] ??
                          notification.targetScreen!,
                    ),
                  ),
                if (notification.createdByName != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Gửi bởi ${notification.createdByName}'),
                  ),
              ],
            ),
            if (isSpecific && names.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Gửi cho: ${names.join(', ')}',
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
