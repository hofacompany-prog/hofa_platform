import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import 'merchant_detail_screen.dart' show merchantTypeLabels;

const merchantStatusLabels = {
  'draft': 'Nháp',
  'pending_review': 'Chờ duyệt',
  'active': 'Đang hoạt động',
  'paused': 'Tạm dừng',
  'rejected': 'Đã từ chối',
  'closed': 'Đã đóng',
};

Color _statusColor(String status, ColorScheme scheme) => switch (status) {
  'active' => Colors.green,
  'pending_review' => Colors.orange,
  'rejected' || 'closed' => scheme.error,
  'paused' => Colors.blueGrey,
  _ => scheme.outline,
};

class MerchantsScreen extends ConsumerStatefulWidget {
  const MerchantsScreen({super.key});

  @override
  ConsumerState<MerchantsScreen> createState() => _MerchantsScreenState();
}

class _MerchantsScreenState extends ConsumerState<MerchantsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _busy = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // cập nhật nút xoá (X) ngay khi gõ/xoá chữ
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => ref.read(merchantSearchProvider.notifier).state = value,
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    ref.read(merchantSearchProvider.notifier).state = '';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(merchantsProvider);
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

  Future<void> _review(Merchant m, bool approve) async {
    var certify = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(approve ? 'Duyệt cửa hàng?' : 'Từ chối cửa hàng?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approve
                    ? '"${m.name}" sẽ được mở bán và hiện với khách hàng.'
                    : '"${m.name}" sẽ bị từ chối và không thể bán hàng.',
              ),
              if (approve) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: certify,
                  onChanged: (v) => setInner(() => certify = v ?? false),
                  title: const Text('Cấp nhãn HOFA Standard'),
                  subtitle: const Text('Được ưu tiên hiển thị với khách'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              style: approve
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(approve ? 'Duyệt' : 'Từ chối'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref
          .read(adminRepoProvider)
          .reviewMerchant(m.id, approve: approve, certifyStandard: certify)
          .then((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchantsAsync = ref.watch(merchantsProvider);
    final theme = Theme.of(context);

    // Dưới ngưỡng này, AppBar không đủ chỗ cho tiêu đề + 3 nút có nhãn chữ (tràn ngang trên
    // điện thoại) — thu 2 nút phụ về icon-only, khớp cách admin_shell.dart quyết định
    // sáng/tối/gọn theo cùng 1 ngưỡng bề rộng.
    final isNarrow = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cửa hàng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(merchantsProvider),
          ),
          const SizedBox(width: 8),
          if (isNarrow)
            IconButton(
              tooltip: 'Trang chủ nổi bật',
              onPressed: () => context.push('/merchants/featured-home'),
              icon: const Icon(Icons.home_outlined),
            )
          else
            OutlinedButton.icon(
              onPressed: () => context.push('/merchants/featured-home'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Trang chủ nổi bật'),
            ),
          const SizedBox(width: 8),
          if (isNarrow)
            IconButton.filled(
              tooltip: 'Tạo cửa hàng',
              onPressed: () => context.push('/merchants/new'),
              icon: const Icon(Icons.add),
            )
          else
            FilledButton.icon(
              onPressed: () => context.push('/merchants/new'),
              icon: const Icon(Icons.add),
              label: const Text('Tạo cửa hàng'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final searchField = TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên cửa hàng...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xoá tìm kiếm',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _clearSearch,
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                );
                final typeDropdown = DropdownButton<String>(
                  value: _typeFilter,
                  onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Mọi loại cửa hàng'),
                    ),
                    ...merchantTypeLabels.entries.map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ),
                  ],
                );
                final statusDropdown = DropdownButton<String>(
                  value: _statusFilter,
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Mọi trạng thái'),
                    ),
                    ...merchantStatusLabels.entries.map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ),
                  ],
                );
                // Dưới 640px, ô tìm kiếm + 2 dropdown không đủ chỗ nằm chung 1 hàng (Row
                // không tự xuống dòng, gây tràn ngang trên điện thoại) — xếp ô tìm kiếm
                // riêng 1 hàng, 2 dropdown xuống hàng dưới trong Wrap để tự ngắt dòng tiếp
                // nếu vẫn chưa đủ chỗ.
                if (constraints.maxWidth < 640) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [typeDropdown, statusDropdown],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 16),
                    typeDropdown,
                    const SizedBox(width: 16),
                    statusDropdown,
                  ],
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: merchantsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final list = all
                    .where(
                      (m) =>
                          _statusFilter == 'all' || m.status == _statusFilter,
                    )
                    .where(
                      (m) =>
                          _typeFilter == 'all' || m.merchantType == _typeFilter,
                    )
                    .toList();
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Không có cửa hàng nào khớp bộ lọc'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatCard(
                          label: 'Tổng cửa hàng (đang lọc)',
                          value: '${list.length}',
                          icon: Icons.storefront_outlined,
                        ),
                      );
                    }
                    final m = list[i];
                    final color = _statusColor(m.status, theme.colorScheme);
                    // Chip + nút duyệt/từ chối gộp vào Wrap riêng dưới hàng tên — trước đây
                    // nằm chung 1 Row với avatar + tên, tràn ra ngoài trên màn hẹp vì có tới
                    // 4 thành phần cỡ cố định (2 chip + tối đa 2 nút) không co giãn được.
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push('/merchants/${m.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    backgroundImage: m.logoUrl != null
                                        ? NetworkImage(m.logoUrl!)
                                        : null,
                                    child: m.logoUrl == null
                                        ? Icon(Icons.storefront, color: color)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                m.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (m.merchantType ==
                                                'standard') ...[
                                              const SizedBox(width: 8),
                                              const Tooltip(
                                                message: 'HOFA Standard',
                                                child: Icon(
                                                  Icons.verified,
                                                  size: 16,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Hoa hồng ${m.commissionRate}% · Đơn tối thiểu ${formatVnd(m.minOrderAmount)}'
                                          '${m.ratingCount > 0 ? ' · ${m.ratingAvg}★ (${m.ratingCount})' : ''}',
                                          style: theme.textTheme.bodySmall,
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
                                    label: Text(
                                      merchantTypeLabels[m.merchantType] ??
                                          m.merchantType,
                                    ),
                                    backgroundColor: theme.colorScheme.secondary
                                        .withValues(alpha: 0.12),
                                    labelStyle: TextStyle(
                                      color: theme.colorScheme.secondary,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Chip(
                                    label: Text(
                                      merchantStatusLabels[m.status] ??
                                          m.status,
                                    ),
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    side: BorderSide(
                                      color: color.withValues(alpha: 0.4),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (m.status == 'pending_review') ...[
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _review(m, true),
                                      child: const Text('Duyệt'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _review(m, false),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.error,
                                      ),
                                      child: const Text('Từ chối'),
                                    ),
                                  ] else if (m.status == 'active')
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => ref
                                                  .read(adminRepoProvider)
                                                  .setMerchantPaused(m.id, true)
                                                  .then((_) {}),
                                            ),
                                      child: const Text('Tạm dừng'),
                                    )
                                  else if (m.status == 'paused')
                                    FilledButton.tonal(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => ref
                                                  .read(adminRepoProvider)
                                                  .setMerchantPaused(
                                                    m.id,
                                                    false,
                                                  )
                                                  .then((_) {}),
                                            ),
                                      child: const Text('Mở lại'),
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
