import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/admin_delivery.dart';
import '../../providers/admin_providers.dart';
import '../../core/responsive.dart';

Color _statusColor(String status, ColorScheme scheme) => switch (status) {
  'delivered' => Colors.green,
  'failed' || 'returned' => scheme.error,
  'pending' => Colors.orange,
  _ => scheme.primary,
};

/// Giám sát TOÀN BỘ chuyến giao hàng của mọi tài xế (không theo từng tài xế riêng) — mặc định
/// chỉ hiện các chuyến đang hoạt động (chưa delivered/failed/returned), admin xem/đổi trạng
/// thái tay/xoá từng chuyến hoặc xoá hàng loạt để gỡ dữ liệu kẹt (vd tài xế thoát app giữa
/// chừng, chuyến đứng hình mãi ở 1 trạng thái).
class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  bool _busy = false;

  Future<void> _forceStatus(AdminDelivery d) async {
    var selected = d.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Chuyển trạng thái chuyến giao hàng'),
          content: SizedBox(
            width: dialogWidth(context, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chỉ đổi đúng cột trạng thái, KHÔNG đụng tồn kho hay ví tài xế (khác lúc tài '
                  'xế tự đổi trong app) — dùng để gỡ chuyến bị kẹt.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: deliveryStatusLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setInner(() => selected = v ?? selected),
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
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).forceDeliveryStatus(d.id, selected);
      ref.invalidate(deliveriesProvider);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã đổi trạng thái')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteOne(AdminDelivery d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá chuyến giao hàng?'),
        content: Text(
          'Chuyến của đơn ${d.orderCode} sẽ bị xoá vĩnh viễn, không thể khôi phục.',
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
      await ref.read(adminRepoProvider).deleteDelivery(d.id);
      ref.invalidate(deliveriesProvider);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xoá chuyến của đơn ${d.orderCode}')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll(String? statusFilter, int count) async {
    if (count == 0) return;
    final scopeText = statusFilter == null
        ? 'đang hoạt động'
        : statusFilter == 'all'
        ? 'TOÀN BỘ (mọi trạng thái, kể cả lịch sử đã giao xong)'
        : 'ở trạng thái "${deliveryStatusLabels[statusFilter] ?? statusFilter}"';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tất cả?'),
        content: Text(
          'Xoá vĩnh viễn $count chuyến giao hàng $scopeText — không thể khôi phục.',
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
      final deleted = statusFilter == null
          ? await ref
                .read(adminRepoProvider)
                .deleteDeliveries(statusIn: activeDeliveryStatuses)
          : statusFilter == 'all'
          ? await ref.read(adminRepoProvider).deleteDeliveries(all: true)
          : await ref
                .read(adminRepoProvider)
                .deleteDeliveries(statusIn: [statusFilter]);
      ref.invalidate(deliveriesProvider);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xoá $deleted chuyến')));
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
    final deliveriesAsync = ref.watch(deliveriesProvider);
    final statusFilter = ref.watch(deliveryStatusFilterProvider);
    final theme = Theme.of(context);
    final count = deliveriesAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chuyến giao hàng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(deliveriesProvider),
          ),
          IconButton(
            tooltip: 'Xoá tất cả đang xem',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _busy || count == 0
                ? null
                : () => _deleteAll(statusFilter, count),
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
                    label: const Text('Đang hoạt động'),
                    selected: statusFilter == null,
                    onSelected: (_) =>
                        ref.read(deliveryStatusFilterProvider.notifier).state =
                            null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: statusFilter == 'all',
                    onSelected: (_) =>
                        ref.read(deliveryStatusFilterProvider.notifier).state =
                            'all',
                  ),
                ),
                ...deliveryStatusLabels.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: statusFilter == e.key,
                      onSelected: (_) =>
                          ref
                                  .read(deliveryStatusFilterProvider.notifier)
                                  .state =
                              e.key,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: deliveriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (deliveries) {
                if (deliveries.isEmpty)
                  return const Center(child: Text('Không có chuyến nào'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: deliveries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = deliveries[i];
                    final color = _statusColor(d.status, theme.colorScheme);
                    // Card tự dựng thay ListTile.trailing — trailing Row cứng (giá + chip +
                    // popup) tràn trên màn hẹp; Wrap bên dưới tự xuống dòng khi hết chỗ.
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: InkWell(
                        onTap: () => context.go('/deliveries/${d.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d.orderCode} · ${d.merchantName ?? ""}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${d.customerName ?? ""} — tài xế: ${d.driverName ?? "chưa gán"}'
                                '${d.driverPhone != null ? " (${d.driverPhone})" : ""}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    formatVnd(d.driverFee),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      deliveryStatusLabels[d.status] ??
                                          d.status,
                                    ),
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    side: BorderSide(
                                      color: color.withValues(alpha: 0.4),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  PopupMenuButton<void>(
                                    icon: const Icon(Icons.more_vert),
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        onTap: () =>
                                            context.go('/orders/${d.orderId}'),
                                        child: const Text('Xem đơn hàng'),
                                      ),
                                      PopupMenuItem(
                                        onTap: () => _forceStatus(d),
                                        child: const Text('Đổi trạng thái'),
                                      ),
                                      PopupMenuItem(
                                        onTap: () => _deleteOne(d),
                                        child: const Text(
                                          'Xoá',
                                          style: TextStyle(color: Colors.red),
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
