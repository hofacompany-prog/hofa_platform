import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../models/order.dart' show orderStatusLabels;
import '../../models/user_profile.dart';
import '../../providers/admin_providers.dart';
import 'users_screen.dart' show roleLabels;

const _driverStatusLabels = {
  'offline': 'Ngoại tuyến',
  'online': 'Trực tuyến',
  'busy': 'Đang bận',
};

/// Xem trước dữ liệu chặn "Xoá vĩnh viễn" 1 người dùng (owner_id/user_id/customer_id đều ON
/// DELETE RESTRICT, xem DELETE /admin/users/:id) — mở từ user_detail_screen.dart để admin đối
/// chiếu trước khi quyết định (chuyển chủ cửa hàng cho Admin, xoá hồ sơ tài xế, hay chỉ "Tạm
/// khoá" thay vì xoá hẳn). Không tự xoá gì — cửa hàng/đơn hàng là dữ liệu của người khác nữa,
/// khác order_blocking_records_screen.dart (bảng sổ sách an toàn để dọn hàng loạt).
class UserBlockingRecordsScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserBlockingRecordsScreen({super.key, required this.userId});

  @override
  ConsumerState<UserBlockingRecordsScreen> createState() =>
      _UserBlockingRecordsScreenState();
}

class _UserBlockingRecordsScreenState
    extends ConsumerState<UserBlockingRecordsScreen> {
  bool _busy = false;

  Future<void> _transferToAdmin(String merchantId, String merchantName) async {
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepoProvider)
          .transferMerchantToAdminOwner(merchantId);
      ref.invalidate(userBlockingRecordsProvider(widget.userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chuyển chủ cửa hàng cho Admin')),
        );
      }
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

  /// Đổi chủ thật cho 1 cửa hàng đang chặn xoá user — CÙNG route PATCH /merchants/:id với
  /// owner_phone/owner_password/owner_full_name mà chính chủ cửa hàng mua hộ hay dùng (xem
  /// resolveOwnerIdByPhone trong merchants.js): có mật khẩu = tạo tài khoản Supabase Auth mới
  /// hẳn cho SĐT chưa từng có, không có mật khẩu = gắn vào 1 SĐT đã có sẵn hồ sơ (role bất kỳ).
  Future<void> _changeOwner(String merchantId, String merchantName) async {
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
    if (mode == null || !mounted) return;

    Map<String, dynamic> payload;
    if (mode == 'existing') {
      final picked = await showDialog<UserProfile>(
        context: context,
        builder: (context) => const _OwnerPickerDialog(),
      );
      if (picked == null) return;
      payload = {'owner_phone': picked.phone};
    } else {
      final entered = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => const _NewOwnerDialog(),
      );
      if (entered == null) return;
      payload = {
        'owner_phone': entered['phone'],
        'owner_password': entered['password'],
        'owner_full_name': entered['full_name'],
      };
    }

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateMerchant(merchantId, payload);
      ref.invalidate(userBlockingRecordsProvider(widget.userId));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã đổi chủ cửa hàng')));
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(userBlockingRecordsProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/users/${widget.userId}'),
        ),
        title: const Text('Dữ liệu chặn xoá người dùng'),
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          final merchants = (data['merchants'] as List)
              .cast<Map<String, dynamic>>();
          final driver = data['driver'] as Map<String, dynamic>?;
          final ordersData = data['orders'] as Map<String, dynamic>;
          final orderItems = (ordersData['items'] as List)
              .cast<Map<String, dynamic>>();
          final orderCount = ordersData['count'] as int;
          final nothingBlocks =
              merchants.isEmpty && driver == null && orderCount == 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    Card(
                      elevation: 0,
                      color: nothingBlocks
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.4,
                            )
                          : theme.colorScheme.errorContainer.withValues(
                              alpha: 0.4,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              nothingBlocks
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_outlined,
                              color: nothingBlocks
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                nothingBlocks
                                    ? '${data['full_name']} — không có gì chặn xoá, có thể xoá vĩnh viễn.'
                                    : '${data['full_name']} — đang bị chặn xoá bởi dữ liệu bên dưới.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (merchants.isNotEmpty) ...[
                      Text('Đang đứng tên cửa hàng', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...merchants.map(
                        (m) => Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          child: ListTile(
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(m['name'] as String),
                            subtitle: Text(
                              '${m['status']}'
                              '${m['merchant_type'] == 'buy_on_behalf' ? ' · Mua hộ' : ''}',
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      context.push('/merchants/${m['id']}'),
                                  child: const Text('Xem'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeOwner(
                                          m['id'] as String,
                                          m['name'] as String,
                                        ),
                                  child: const Text('Đổi chủ mới'),
                                ),
                                FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _transferToAdmin(
                                          m['id'] as String,
                                          m['name'] as String,
                                        ),
                                  child: const Text('Chuyển cho Admin'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (driver != null) ...[
                      Text('Hồ sơ tài xế', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: ListTile(
                          leading: const Icon(Icons.two_wheeler_outlined),
                          title: Text(
                            '${driver['vehicle_type'] ?? "Xe"} · ${driver['vehicle_plate'] ?? "—"}',
                          ),
                          subtitle: Text(
                            _driverStatusLabels[driver['status']] ??
                                driver['status'] as String,
                          ),
                          trailing: TextButton(
                            onPressed: () => context.push('/drivers'),
                            child: const Text('Xem ở màn Tài xế'),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          'Xoá hồ sơ tài xế ở màn Tài xế trước, sau đó mới xoá được người dùng này.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (orderCount > 0) ...[
                      Text(
                        'Đơn hàng đã đặt ($orderCount${orderItems.length < orderCount ? ', hiện ${orderItems.length} gần nhất' : ''})',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Column(
                          children: orderItems
                              .map(
                                (o) => ListTile(
                                  title: Text(o['order_code'] as String? ?? o['id'] as String),
                                  subtitle: Text(
                                    '${orderStatusLabels[o['status']] ?? o['status']} · '
                                    '${formatVnd((o['total_amount'] as num?) ?? 0)}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context.push('/orders/${o['id']}'),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Xoá sẽ mất luôn dữ liệu đơn/doanh thu — dùng "Tạm khoá" ở màn chi tiết '
                          'người dùng nếu chỉ muốn chặn đăng nhập.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tìm + chọn 1 người dùng có sẵn (mọi role — resolveOwnerIdByPhone chấp nhận SĐT của bất kỳ
/// role nào, tự tạo thêm hồ sơ merchant_owner riêng dùng chung auth_user_id) làm chủ mới cho 1
/// cửa hàng. Cùng pattern _UserPickerDialog ở notifications_screen.dart, chỉ khác chọn 1 thay vì
/// nhiều (tap là chọn luôn, không cần nút "Xong").
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
/// dùng SĐT này) — trả về map để _changeOwner gọi PATCH /merchants/:id với owner_password kèm
/// theo, cho chủ mới tự đăng nhập app Cửa hàng ngay bằng đúng SĐT/mật khẩu này.
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
