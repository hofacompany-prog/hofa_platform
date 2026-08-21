import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/issue_report.dart';
import '../../providers/admin_providers.dart';

/// Danh sách báo cáo sự cố tài xế báo cáo cửa hàng (kèm đánh giá khách hàng) / cửa hàng báo cáo
/// tài xế — xem POST /issue-reports (driver app, store app), hofa-db/92_issue_reports.sql.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final Set<String> _busyIds = {};

  Future<void> _resolve(IssueReport r) async {
    final noteCtrl = TextEditingController(text: r.adminNote ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đánh dấu đã xử lý?'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Ghi chú xử lý (không bắt buộc)',
            border: OutlineInputBorder(),
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
    );
    if (ok != true) return;

    setState(() => _busyIds.add(r.id));
    try {
      await ref
          .read(adminRepoProvider)
          .resolveIssueReport(r.id, adminNote: noteCtrl.text.trim());
      ref.invalidate(issueReportsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportsAsync = ref.watch(issueReportsProvider);
    final status = ref.watch(issueReportStatusFilterProvider);
    final reporterType = ref.watch(issueReportReporterFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(issueReportsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Chưa xử lý'),
                  selected: status == 'open',
                  onSelected: (_) => ref
                      .read(issueReportStatusFilterProvider.notifier)
                      .state = 'open',
                ),
                FilterChip(
                  label: const Text('Đã xử lý'),
                  selected: status == 'resolved',
                  onSelected: (_) => ref
                      .read(issueReportStatusFilterProvider.notifier)
                      .state = 'resolved',
                ),
                FilterChip(
                  label: const Text('Tất cả'),
                  selected: status == null,
                  onSelected: (_) => ref
                      .read(issueReportStatusFilterProvider.notifier)
                      .state = null,
                ),
                const VerticalDivider(width: 24),
                ChoiceChip(
                  label: const Text('Từ tài xế'),
                  selected: reporterType == 'driver',
                  onSelected: (v) => ref
                      .read(issueReportReporterFilterProvider.notifier)
                      .state = v ? 'driver' : null,
                ),
                ChoiceChip(
                  label: const Text('Từ cửa hàng'),
                  selected: reporterType == 'merchant',
                  onSelected: (v) => ref
                      .read(issueReportReporterFilterProvider.notifier)
                      .state = v ? 'merchant' : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: reportsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (reports) {
                if (reports.isEmpty) {
                  return const Center(child: Text('Không có báo cáo nào'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: reports.length,
                  itemBuilder: (context, i) {
                    final r = reports[i];
                    final busy = _busyIds.contains(r.id);
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  r.isDriverReport
                                      ? Icons.two_wheeler_outlined
                                      : Icons.storefront_outlined,
                                  size: 18,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${r.isDriverReport ? 'Tài xế' : 'Cửa hàng'} '
                                    '${r.reporterName ?? ''}'
                                    '${r.reporterPhone != null ? ' — ${r.reporterPhone}' : ''} '
                                    'báo cáo',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatDateTime(r.createdAt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () =>
                                  context.push('/orders/${r.orderId}'),
                              child: Text(
                                '${r.orderCode} · ${r.merchantName}',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: r.issueTypes
                                  .map(
                                    (t) => Chip(
                                      label: Text(
                                        issueTypeLabel(r.reporterType, t),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                  .toList(),
                            ),
                            if (r.waitMinutes != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Khoảng ${r.waitMinutes} phút'),
                              ),
                            if (r.note != null && r.note!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Ghi chú: ${r.note}'),
                              ),
                            if (r.customerRating != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    Text(
                                      'Đánh giá khách "${r.customerName ?? ''}": ',
                                    ),
                                    ...List.generate(
                                      5,
                                      (i) => Icon(
                                        i < r.customerRating!
                                            ? Icons.star
                                            : Icons.star_border,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (r.status == 'resolved') ...[
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Đã xử lý'
                                      '${r.adminNote != null && r.adminNote!.isNotEmpty ? ' — ${r.adminNote}' : ''}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  onPressed: busy ? null : () => _resolve(r),
                                  child: busy
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Đánh dấu đã xử lý'),
                                ),
                              ),
                            ],
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
