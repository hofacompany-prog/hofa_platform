import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';

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
  String _statusFilter = 'all';
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(merchantsProvider);
      ref.invalidate(statsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
              Text(approve
                  ? '"${m.name}" sẽ được mở bán và hiện với khách hàng.'
                  : '"${m.name}" sẽ bị từ chối và không thể bán hàng.'),
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(
              style: approve ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(approve ? 'Duyệt' : 'Từ chối'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() =>
        ref.read(adminRepoProvider).reviewMerchant(m.id, approve: approve, certifyStandard: certify).then((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final merchantsAsync = ref.watch(merchantsProvider);
    final theme = Theme.of(context);

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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo tên cửa hàng...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) => ref.read(merchantSearchProvider.notifier).state = v,
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _statusFilter,
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Mọi trạng thái')),
                    ...merchantStatusLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                  ],
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: merchantsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final list =
                    _statusFilter == 'all' ? all : all.where((m) => m.status == _statusFilter).toList();
                if (list.isEmpty) {
                  return const Center(child: Text('Không có cửa hàng nào khớp bộ lọc'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final color = _statusColor(m.status, theme.colorScheme);
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.12),
                              backgroundImage: m.logoUrl != null ? NetworkImage(m.logoUrl!) : null,
                              child: m.logoUrl == null ? Icon(Icons.storefront, color: color) : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(m.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      if (m.merchantType == 'standard') ...[
                                        const SizedBox(width: 8),
                                        const Tooltip(
                                          message: 'HOFA Standard',
                                          child: Icon(Icons.verified, size: 16, color: Colors.blue),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hoa hồng ${m.commissionRate}% · Đơn tối thiểu ${formatVnd(m.minOrderAmount)}'
                                    '${m.ratingCount > 0 ? ' · ${m.ratingAvg}★ (${m.ratingCount})' : ''}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Chip(
                              label: Text(merchantStatusLabels[m.status] ?? m.status),
                              backgroundColor: color.withValues(alpha: 0.12),
                              side: BorderSide(color: color.withValues(alpha: 0.4)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            if (m.status == 'pending_review') ...[
                              FilledButton(
                                onPressed: _busy ? null : () => _review(m, true),
                                child: const Text('Duyệt'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _busy ? null : () => _review(m, false),
                                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                child: const Text('Từ chối'),
                              ),
                            ] else if (m.status == 'active')
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() =>
                                        ref.read(adminRepoProvider).setMerchantPaused(m.id, true).then((_) {})),
                                child: const Text('Tạm dừng'),
                              )
                            else if (m.status == 'paused')
                              FilledButton.tonal(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() =>
                                        ref.read(adminRepoProvider).setMerchantPaused(m.id, false).then((_) {})),
                                child: const Text('Mở lại'),
                              ),
                          ],
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
