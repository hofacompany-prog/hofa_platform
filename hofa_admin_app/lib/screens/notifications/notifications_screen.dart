import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/admin_notification.dart';
import '../../models/merchant.dart';
import '../../models/notification_inbox_item.dart';
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import '../../core/responsive.dart';

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

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  String _audienceType = 'customer';
  bool _sendToAll = true;
  bool _showBadge = false;
  String? _targetScreen;
  String _category = 'system';
  final List<UserProfile> _selectedUsers = [];
  final List<Merchant> _selectedMerchants = [];

  int? _allAudienceCount;
  bool _loadingAllAudience = false;
  int? _specificAudienceCount;
  bool _loadingSpecificAudience = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllAudienceCount();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
            category: _category,
          );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _selectedUsers.clear();
        _selectedMerchants.clear();
        _category = 'system';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Gửi thông báo'),
            Tab(text: 'Hộp thư theo cửa hàng'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSendTab(theme, historyAsync), const _InboxTab()],
      ),
    );
  }

  Widget _buildSendTab(
    ThemeData theme,
    AsyncValue<List<AdminNotification>> historyAsync,
  ) {
    final typeLabel = audienceTypeLabels[_audienceType]!;
    final typeLabelLower = typeLabel.toLowerCase();
    final selectionCount = _audienceType == 'merchant'
        ? _selectedMerchants.length
        : _selectedUsers.length;

    return ListView(
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
                                              () =>
                                                  _selectedMerchants.remove(m),
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
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration: const InputDecoration(
                            labelText: 'Danh mục thông báo',
                            helperText:
                                'Quyết định thông báo này nằm ở tab nào trong hộp thư của người nhận.',
                            border: OutlineInputBorder(),
                          ),
                          items: notificationCategoryLabels.entries
                              .where((e) => e.key != 'order')
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: _sending
                              ? null
                              : (v) =>
                                    setState(() => _category = v ?? _category),
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
                          children: [
                            ...items.map(
                              (n) => _NotificationCard(notification: n),
                            ),
                            const SizedBox(height: 16),
                            StatCard(
                              label: 'Tổng thông báo đã gửi',
                              value: '${items.length}',
                              icon: Icons.history_outlined,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
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
        width: dialogWidth(context, 480),
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
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    notificationCategoryLabels[notification.category] ??
                        notification.category,
                  ),
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
                      notificationTargetScreensByAudience[notification
                              .audienceType]?[notification.targetScreen] ??
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

/// Hộp thư THẬT của từng người nhận thuộc 1 cửa hàng — chọn cửa hàng trước (merchant_id bắt
/// buộc ở server, tránh tải cả bảng notifications không lọc gì), sau đó xem/chọn/xoá 1 hoặc
/// nhiều dòng, hoặc xoá cả hộp thư của cửa hàng đó. Cài đặt tự xoá theo thời gian (TTL) nằm
/// ngay trong tab này vì nó chỉ ảnh hưởng tới đúng dữ liệu đang xem ở đây.
class _InboxTab extends ConsumerStatefulWidget {
  const _InboxTab();

  @override
  ConsumerState<_InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends ConsumerState<_InboxTab> {
  String _audienceType = 'customer';
  bool _all = true;
  final List<UserProfile> _selectedUsers = [];
  final List<Merchant> _selectedMerchants = [];
  final Set<String> _selectedIds = {};

  bool _loading = false;
  bool _busy = false;
  String? _error;
  List<NotificationInboxItem>? _items;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  bool get _hasAudience =>
      _all ||
      (_audienceType == 'merchant'
          ? _selectedMerchants.isNotEmpty
          : _selectedUsers.isNotEmpty);

  List<String>? get _merchantIds => _audienceType == 'merchant' && !_all
      ? _selectedMerchants.map((m) => m.id).toList()
      : null;

  List<String>? get _userIds => _audienceType != 'merchant' && !_all
      ? _selectedUsers.map((u) => u.id).toList()
      : null;

  Future<void> _loadItems() async {
    if (!_hasAudience) {
      setState(() {
        _items = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(adminRepoProvider)
          .notificationInbox(
            audienceType: _audienceType,
            merchantIds: _merchantIds,
            userIds: _userIds,
          );
      if (mounted) {
        setState(() {
          _items = items;
          _selectedIds.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onAudienceTypeChanged(String type) {
    if (type == _audienceType || _busy) return;
    setState(() {
      _audienceType = type;
      _selectedUsers.clear();
      _selectedMerchants.clear();
    });
    _loadItems();
  }

  void _onAllChanged(bool value) {
    if (value == _all || _busy) return;
    setState(() => _all = value);
    _loadItems();
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
    _loadItems();
  }

  Future<void> _deleteIds(List<String> ids, {String? confirmLabel}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirmLabel ?? 'Xoá ${ids.length} thông báo đã chọn?'),
        content: const Text(
          'Không thể hoàn tác — người nhận sẽ không còn thấy các dòng này trong hộp thư nữa.',
        ),
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
      await ref.read(adminRepoProvider).deleteNotificationInbox(ids: ids);
      await _loadItems();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAllInScope() async {
    final typeLabelLower = audienceTypeLabels[_audienceType]!.toLowerCase();
    final scopeLabel = _all
        ? 'TOÀN BỘ $typeLabelLower'
        : '${(_merchantIds ?? _userIds ?? const []).length} $typeLabelLower đã chọn';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá hộp thư của $scopeLabel?'),
        content: const Text(
          'Xoá hết mọi thông báo (cả cũ lẫn mới, đã đọc lẫn chưa đọc) trong phạm vi đang chọn. '
          'Không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final deleted = await ref
          .read(adminRepoProvider)
          .deleteNotificationInbox(
            audienceType: _audienceType,
            merchantIds: _merchantIds,
            userIds: _userIds,
          );
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá $deleted thông báo')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAllGlobal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá TOÀN BỘ hộp thư của TẤT CẢ người dùng?'),
        content: const Text(
          'Xoá hết mọi thông báo của MỌI khách hàng, cửa hàng, tài xế trên toàn hệ thống — '
          'không chỉ phạm vi đang xem. Không thể hoàn tác. Chỉ dùng khi thật sự cần dọn sạch '
          'toàn bộ dữ liệu hộp thư.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá toàn bộ hệ thống'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final deleted = await ref
          .read(adminRepoProvider)
          .deleteNotificationInbox(all: true);
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xoá $deleted thông báo trên toàn hệ thống'),
          ),
        );
      }
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
    final theme = Theme.of(context);
    final typeLabel = audienceTypeLabels[_audienceType]!;
    final typeLabelLower = typeLabel.toLowerCase();
    final selectionCount = _audienceType == 'merchant'
        ? _selectedMerchants.length
        : _selectedUsers.length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _TtlSettingsCard(),
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
                                  onSelected: _busy
                                      ? null
                                      : (_) => _onAudienceTypeChanged(e.key),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Xem hộp thư của',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        RadioGroup<bool>(
                          groupValue: _all,
                          onChanged: (v) {
                            if (v != null) _onAllChanged(v);
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
                        if (!_all) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _pickEntities,
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
                                    onDeleted: _busy
                                        ? null
                                        : () {
                                            setState(
                                              () =>
                                                  _selectedMerchants.remove(m),
                                            );
                                            _loadItems();
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
                                    onDeleted: _busy
                                        ? null
                                        : () {
                                            setState(
                                              () => _selectedUsers.remove(u),
                                            );
                                            _loadItems();
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
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _busy ? null : _deleteAllGlobal,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Xoá toàn bộ thông báo trên toàn hệ thống'),
                ),
                const SizedBox(height: 12),
                if (!_hasAudience)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'Chọn ít nhất 1 $typeLabelLower cụ thể ở trên để xem hộp thư.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  )
                else if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Text('Lỗi: $_error')
                else if (_items == null || _items!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'Không có thông báo nào trong phạm vi này.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final items = _items!;
                      final allSelected = _selectedIds.length == items.length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Wrap thay Row+Spacer — nhãn nút dài ("Xoá tất cả trong phạm vi
                          // này") tràn ra ngoài trên màn hẹp nếu ép nằm chung 1 hàng.
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: allSelected,
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() {
                                            if (v == true) {
                                              _selectedIds
                                                ..clear()
                                                ..addAll(
                                                  items.map((e) => e.id),
                                                );
                                            } else {
                                              _selectedIds.clear();
                                            }
                                          }),
                                  ),
                                  Text(
                                    'Chọn tất cả (${items.length})',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              if (_selectedIds.isNotEmpty)
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _deleteIds(_selectedIds.toList()),
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Xoá đã chọn (${_selectedIds.length})',
                                  ),
                                ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _deleteAllInScope,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                ),
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Xoá tất cả trong phạm vi này',
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                          ...items.map(
                            (n) => _InboxRow(
                              item: n,
                              selected: _selectedIds.contains(n.id),
                              onSelectedChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                      if (v == true) {
                                        _selectedIds.add(n.id);
                                      } else {
                                        _selectedIds.remove(n.id);
                                      }
                                    }),
                              onDelete: _busy
                                  ? null
                                  : () => _deleteIds([
                                      n.id,
                                    ], confirmLabel: 'Xoá thông báo này?'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          StatCard(
                            label: 'Tổng thông báo',
                            value: '${items.length}',
                            icon: Icons.mark_email_unread_outlined,
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InboxRow extends StatelessWidget {
  final NotificationInboxItem item;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;
  final VoidCallback? onDelete;

  const _InboxRow({
    required this.item,
    required this.selected,
    required this.onSelectedChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: onSelectedChanged,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(item.recipientName),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    notificationCategoryLabels[item.category] ?? item.category,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(item.isRead ? 'Đã đọc' : 'Chưa đọc'),
                  backgroundColor: item.isRead
                      ? null
                      : theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(formatDateTime(item.createdAt)),
                ),
              ],
            ),
          ],
        ),
        secondary: IconButton(
          tooltip: 'Xoá thông báo này',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

/// Cấu hình số ngày/giờ 1 thông báo được giữ trong hộp thư trước khi bị sweep nền tự xoá
/// (server/src/push.js sweepOldNotifications, quét mỗi giờ) — để trống nghĩa là không tự xoá.
class _TtlSettingsCard extends ConsumerStatefulWidget {
  const _TtlSettingsCard();

  @override
  ConsumerState<_TtlSettingsCard> createState() => _TtlSettingsCardState();
}

class _TtlSettingsCardState extends ConsumerState<_TtlSettingsCard> {
  final _valueCtrl = TextEditingController();
  String _unit = 'days';
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  void _applySettings(int? ttlHours) {
    if (ttlHours == null) {
      _valueCtrl.text = '';
      _unit = 'days';
    } else if (ttlHours % 24 == 0) {
      _valueCtrl.text = (ttlHours ~/ 24).toString();
      _unit = 'days';
    } else {
      _valueCtrl.text = ttlHours.toString();
      _unit = 'hours';
    }
  }

  Future<void> _save() async {
    final raw = _valueCtrl.text.trim();
    int? ttlHours;
    if (raw.isNotEmpty) {
      final value = int.tryParse(raw);
      if (value == null || value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nhập số nguyên dương, hoặc để trống để không tự xoá',
            ),
          ),
        );
        return;
      }
      ttlHours = _unit == 'days' ? value * 24 : value;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminRepoProvider).updateNotificationTtl(ttlHours);
      ref.invalidate(notificationSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ttlHours == null
                  ? 'Đã tắt tự xoá'
                  : 'Đã lưu — tự xoá sau $raw ${_unit == 'days' ? 'ngày' : 'giờ'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(notificationSettingsProvider);

    settingsAsync.whenData((s) {
      if (!_initialized) {
        _initialized = true;
        _applySettings(s.ttlHours);
      }
    });

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tự động xoá thông báo cũ', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Sau khoảng thời gian này, thông báo tự bị xoá khỏi hộp thư của MỌI người dùng '
              '(kiểm tra mỗi giờ). Để trống thì không bao giờ tự xoá.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            // Ô nhập cỡ cố định + dropdown + nút Lưu cộng lại dễ vượt bề rộng card trên màn
            // hẹp — cuộn ngang thay vì để RenderFlex overflow.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _valueCtrl,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sống được',
                        hintText: 'Để trống',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _unit,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _unit = v ?? _unit),
                    items: const [
                      DropdownMenuItem(value: 'days', child: Text('Ngày')),
                      DropdownMenuItem(value: 'hours', child: Text('Giờ')),
                    ],
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Lưu'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
