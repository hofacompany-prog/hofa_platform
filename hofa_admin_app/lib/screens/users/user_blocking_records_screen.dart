import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/order.dart' show orderStatusLabels;
import '../../providers/admin_providers.dart';

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
