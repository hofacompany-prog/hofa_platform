import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/format.dart';
import '../../models/order.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

final _yyyyMMdd = DateFormat('yyyy-MM-dd');

Color statusColor(String status, ColorScheme scheme) => switch (status) {
  'completed' || 'delivered' => Colors.green,
  'cancelled' || 'refunded' => scheme.error,
  'pending_payment' => Colors.orange,
  _ => scheme.primary,
};

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  // Chế độ chọn nhiều để xoá hàng loạt — bấm giữ 1 thẻ đơn để bật, bấm "Huỷ" hoặc xoá xong để
  // tắt. Giữ Set<String> id thay vì index vì danh sách có thể đổi thứ tự/độ dài giữa các lần
  // ordersProvider tự tải lại (đổi bộ lọc, kéo mới...).
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// Xoá lần lượt từng đơn đã chọn — đơn nào bị chặn (còn ràng buộc dữ liệu, vd đã có giao dịch
  /// thanh toán/ví) thì bỏ qua, gộp báo cáo 1 lần cuối thay vì dừng cả loạt giữa chừng. Muốn xử
  /// lý riêng đơn bị chặn thì vào đúng màn chi tiết đơn đó dùng "Xem ràng buộc" như xoá đơn lẻ.
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá các đơn đã chọn?'),
        content: Text(
          'Xoá vĩnh viễn ${ids.length} đơn hàng đã chọn. Đơn nào còn ràng buộc dữ liệu '
          '(đã có giao dịch thanh toán/ví...) sẽ không xoá được, cần xử lý riêng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final repo = ref.read(adminRepoProvider);
    var deleted = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.deleteOrder(id);
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    ref.invalidate(ordersProvider);
    if (!mounted) return;
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Đã xoá $deleted đơn'
              : 'Đã xoá $deleted đơn — $failed đơn không xoá được (còn ràng buộc dữ liệu)',
        ),
      ),
    );
  }

  /// Ngoại lệ chỉ admin có — app khách/cửa hàng bắt buộc chọn 1 trong 4 khoảng nhanh (Hôm nay/
  /// Hôm qua/Tuần qua/Tháng qua), còn admin chọn khoảng ngày tuỳ ý để vẫn xem được TẤT CẢ đơn
  /// (để trống from/to) hoặc thu hẹp theo đúng khoảng cần tra.
  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final from = ref.read(orderFromDateProvider);
    final to = ref.read(orderToDateProvider);
    final initial = from != null && to != null
        ? DateTimeRange(start: DateTime.parse(from), end: DateTime.parse(to))
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: initial,
      helpText: 'Chọn khoảng thời gian',
    );
    if (picked == null) return;
    ref.read(orderFromDateProvider.notifier).state = _yyyyMMdd.format(
      picked.start,
    );
    ref.read(orderToDateProvider.notifier).state = _yyyyMMdd.format(picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    final statusFilter = ref.watch(orderStatusFilterProvider);
    final needsDriverFilter = ref.watch(orderNeedsDriverFilterProvider);
    final fromDate = ref.watch(orderFromDateProvider);
    final toDate = ref.watch(orderToDateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                tooltip: 'Huỷ chọn',
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text('Đã chọn ${_selectedIds.length}'),
              actions: [
                IconButton(
                  tooltip: 'Xoá đã chọn',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              title: const Text('Đơn hàng'),
              actions: [
                if (fromDate != null && toDate != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text('$fromDate → $toDate'),
                      onDeleted: () {
                        ref.read(orderFromDateProvider.notifier).state = null;
                        ref.read(orderToDateProvider.notifier).state = null;
                      },
                      onPressed: () => _pickDateRange(context, ref),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateRange(context, ref),
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('Chọn khoảng thời gian'),
                    ),
                  ),
                IconButton(
                  tooltip: 'Tải lại',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(ordersProvider),
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
                    selected: statusFilter == null && !needsDriverFilter,
                    onSelected: (_) {
                      ref.read(orderNeedsDriverFilterProvider.notifier).state =
                          false;
                      ref.read(orderStatusFilterProvider.notifier).state = null;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.two_wheeler_outlined, size: 18),
                    label: const Text('Mua hộ cần tài xế'),
                    selected: needsDriverFilter,
                    onSelected: (v) =>
                        ref
                                .read(orderNeedsDriverFilterProvider.notifier)
                                .state =
                            v,
                  ),
                ),
                ...orderStatusLabels.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: !needsDriverFilter && statusFilter == e.key,
                      onSelected: (_) {
                        ref
                                .read(orderNeedsDriverFilterProvider.notifier)
                                .state =
                            false;
                        ref.read(orderStatusFilterProvider.notifier).state =
                            e.key;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (orders) {
                if (orders.isEmpty)
                  return const Center(child: Text('Không có đơn nào'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: orders.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == orders.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatCard(
                          label: 'Tổng đơn (đang lọc)',
                          value: '${orders.length}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      );
                    }
                    final o = orders[i];
                    final color = statusColor(o.status, theme.colorScheme);
                    final selected = _selectedIds.contains(o.id);
                    return Card(
                      elevation: 0,
                      color: selected
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.4,
                            )
                          : theme.colorScheme.surfaceContainerLow,
                      child: InkWell(
                        onTap: _selectionMode
                            ? () => _toggleSelection(o.id)
                            : () => context.go('/orders/${o.id}'),
                        onLongPress: _selectionMode
                            ? null
                            : () => _enterSelectionMode(o.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectionMode) ...[
                                Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggleSelection(o.id),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${o.orderCode} · ${o.merchantName ?? ""}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${o.customerName ?? o.shipRecipientName} — ${formatDateTime(o.createdAt)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          formatVnd(o.totalAmount),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            orderStatusLabels[o.status] ??
                                                o.status,
                                          ),
                                          labelStyle: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          backgroundColor: color.withValues(
                                            alpha: 0.12,
                                          ),
                                          side: BorderSide(
                                            color: color.withValues(alpha: 0.4),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                  ],
                                ),
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
