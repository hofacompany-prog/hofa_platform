import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/permission_helper.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import '../orders/orders_screen.dart' show statusColor;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkPermissionsOnStart(),
    );
  }

  Future<void> _checkPermissionsOnStart() async {
    final notif = await PermissionHelper.notificationState();
    final loc = await PermissionHelper.locationState();
    if (!mounted) return;
    final missing = <String>[
      if (notif != PermissionState.granted) 'Thông báo đẩy',
      if (loc != PermissionState.granted) 'Vị trí',
    ];
    if (missing.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cần cấp quyền để dùng app tốt hơn'),
        content: Text(
          'Web admin cần quyền ${missing.join(' và ')} để báo có đơn/yêu cầu cần xử lý kịp thời '
          'và xác định đúng vị trí lúc chọn toạ độ trên bản đồ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (notif != PermissionState.granted) {
                await PermissionHelper.requestNotification(context);
              }
              if (loc != PermissionState.granted && mounted) {
                await PermissionHelper.requestLocation(context);
              }
            },
            child: const Text('Cấp quyền ngay'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng quan'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(statsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Không tải được số liệu: $e')),
        data: (s) => LayoutBuilder(
          builder: (context, constraints) {
            // 2 cột trên điện thoại từng làm chữ (nhất là "sub" 2 số liệu gộp 1 dòng) bị bóp
            // tràn/mất chữ — dưới 500 chỉ còn 1 cột, mỗi thẻ chiếm hết bề ngang, đủ chỗ hiện
            // trọn số liệu. Thẻ 1 cột cũng không cần cao bằng thẻ nhiều cột (aspectRatio thấp
            // hơn = thẻ thấp/rộng hơn) vì đã có sẵn đủ bề ngang.
            final columns = constraints.maxWidth > 1200
                ? 4
                : constraints.maxWidth > 800
                ? 3
                : constraints.maxWidth > 500
                ? 2
                : 1;
            final aspectRatio = columns == 1 ? 2.6 : 1.6;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: aspectRatio,
                    children: [
                      StatCard(
                        label: 'Đơn hôm nay',
                        value: '${s.orders.today}',
                        sub:
                            'Tổng ${s.orders.total} đơn · ${s.orders.inProgress} đang chạy',
                        icon: Icons.receipt_long,
                      ),
                      StatCard(
                        label: 'Doanh thu đã giao',
                        value: formatVnd(s.revenue.gross),
                        sub:
                            'HOFA thu hoa hồng ${formatVnd(s.revenue.commission)}',
                        icon: Icons.payments,
                        accent: Colors.teal,
                      ),
                      StatCard(
                        label: 'Cửa hàng',
                        value: '${s.merchants.active}',
                        sub:
                            '${s.merchants.pendingReview} chờ duyệt · ${s.merchants.paused} tạm dừng',
                        icon: Icons.storefront,
                        accent: Colors.indigo,
                      ),
                      StatCard(
                        label: 'Người dùng',
                        value: '${s.users.total}',
                        sub:
                            '${s.users.customers} khách · ${s.users.drivers} tài xế',
                        icon: Icons.people,
                        accent: Colors.orange,
                      ),
                    ],
                  ),
                  if (s.merchants.pendingReview > 0) ...[
                    const SizedBox(height: 24),
                    Card(
                      color: theme.colorScheme.tertiaryContainer,
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.pending_actions),
                        title: Text(
                          '${s.merchants.pendingReview} cửa hàng đang chờ bạn duyệt',
                        ),
                        trailing: FilledButton(
                          onPressed: () => context.go('/merchants'),
                          child: const Text('Xem ngay'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('Đơn hàng gần đây', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  // SizedBox ép full-width — không có gì bắt buộc Card giãn hết bề ngang, nên khi
                  // có đơn (nội dung chỉ rộng bằng mã đơn/giá tiền) Card co lại theo, chỉ tình cờ
                  // đầy khi trống vì Center bên trong tự giãn hết cỡ.
                  SizedBox(
                    width: double.infinity,
                    child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: s.recentOrders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Chưa có đơn hàng nào')),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: s.recentOrders
                                .map((o) {
                                  final color = statusColor(
                                    o.status,
                                    theme.colorScheme,
                                  );
                                  return InkWell(
                                    onTap: () => context.go('/orders/${o.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      // Row thay vì gộp chung 1 Column — chữ (mã đơn/khách) neo
                                      // trái qua Expanded, trạng thái neo phải qua Column riêng,
                                      // dù Card đã full-width thì bố cục vẫn đúng ý (không phải
                                      // co theo bề rộng nội dung như Wrap trước đây).
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${o.orderCode} · ${o.merchantName}',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${o.customerName} — ${formatDateTime(o.createdAt)}',
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                formatVnd(o.totalAmount),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Chip(
                                                label: Text(
                                                  orderStatusLabels[o.status] ??
                                                      o.status,
                                                ),
                                                labelStyle: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                backgroundColor: color
                                                    .withValues(alpha: 0.12),
                                                side: BorderSide(
                                                  color: color.withValues(
                                                    alpha: 0.4,
                                                  ),
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
