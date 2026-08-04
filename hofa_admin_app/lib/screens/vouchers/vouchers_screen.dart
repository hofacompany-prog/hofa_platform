import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../models/voucher.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

const _discountTypeLabels = {
  'percent': 'Phần trăm (%)',
  'fixed': 'Số tiền cố định',
  'free_shipping': 'Miễn phí vận chuyển',
};

const _statusFilters = ['Tất cả', 'Đang chạy', 'Đã tắt', 'Hết hạn/hết lượt'];

/// Quản lý voucher toàn sàn/theo cửa hàng. isPublic=true là voucher "chọn" — hiện thành
/// danh sách cho khách bấm áp dụng ở app khách (kiểu Shopee), không cần gõ mã. isPublic=
/// false là voucher "nhập chữ" — chỉ dùng được khi khách tự gõ đúng mã.
class VouchersScreen extends ConsumerStatefulWidget {
  const VouchersScreen({super.key});

  @override
  ConsumerState<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends ConsumerState<VouchersScreen> {
  bool _busy = false;
  String _search = '';
  String _statusFilter = 'Tất cả';

  Future<void> _voucherDialog(
    List<Merchant> merchants, {
    Voucher? existing,
  }) async {
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final valueCtrl = TextEditingController(
      text: existing == null ? '' : existing.discountValue.toString(),
    );
    final maxDiscountCtrl = TextEditingController(
      text: existing?.maxDiscount?.toString() ?? '',
    );
    final minOrderCtrl = TextEditingController(
      text: existing?.minOrderAmount.toString() ?? '0',
    );
    final usageLimitCtrl = TextEditingController(
      text: existing?.usageLimit?.toString() ?? '',
    );
    final usageLimitPerUserCtrl = TextEditingController(
      text: existing?.usageLimitPerUser.toString() ?? '1',
    );
    String? merchantId = existing?.merchantId;
    String discountType = existing?.discountType ?? 'percent';
    var startsAt = existing?.startsAt ?? DateTime.now();
    var endsAt = existing?.endsAt;
    var isPublic = existing?.isPublic ?? false;
    var isActive = existing?.isActive ?? true;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) {
          Future<void> pickStartsAt() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: startsAt,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            );
            if (picked != null) setInner(() => startsAt = picked);
          }

          Future<void> pickEndsAt() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: endsAt ?? startsAt.add(const Duration(days: 30)),
              firstDate: startsAt,
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            );
            if (picked != null) setInner(() => endsAt = picked);
          }

          return AlertDialog(
            title: Text(existing == null ? 'Tạo voucher' : 'Sửa voucher'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Mã voucher',
                        hintText: 'VD: GIAM10, FREESHIP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: merchantId,
                      decoration: const InputDecoration(
                        labelText: 'Phạm vi áp dụng',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Toàn sàn HOFA'),
                        ),
                        ...merchants.map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setInner(() => merchantId = v),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả (không bắt buộc)',
                        hintText: 'VD: Giảm giá mừng khai trương',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loại giảm giá',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: _discountTypeLabels.entries
                          .map(
                            (e) => ButtonSegment(
                              value: e.key,
                              label: Text(e.value),
                            ),
                          )
                          .toList(),
                      selected: {discountType},
                      onSelectionChanged: (s) =>
                          setInner(() => discountType = s.first),
                    ),
                    const SizedBox(height: 16),
                    if (discountType != 'free_shipping') ...[
                      TextField(
                        controller: valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: discountType == 'percent'
                              ? 'Phần trăm giảm (%)'
                              : 'Số tiền giảm (VNĐ)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (discountType == 'percent') ...[
                      TextField(
                        controller: maxDiscountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText:
                              'Giảm tối đa (VNĐ, để trống = không giới hạn)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: minOrderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá trị đơn hàng tối thiểu (VNĐ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Giới hạn lượt dùng',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: usageLimitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tổng lượt (trống = không giới hạn)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: usageLimitPerUserCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Lượt/khách',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Thời gian hiệu lực',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text('Từ ${formatDate(startsAt)}'),
                            onPressed: pickStartsAt,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              endsAt == null
                                  ? 'Không giới hạn'
                                  : 'Đến ${formatDate(endsAt!)}',
                            ),
                            onPressed: pickEndsAt,
                          ),
                        ),
                        if (endsAt != null)
                          IconButton(
                            tooltip: 'Bỏ ngày kết thúc',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setInner(() => endsAt = null),
                          ),
                      ],
                    ),
                    const Divider(height: 32),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hiện cho khách chọn'),
                      subtitle: const Text(
                        'Bật: hiện thành danh sách để khách bấm áp dụng (kiểu Shopee), '
                        'không cần gõ mã. Tắt: khách phải tự nhập đúng mã mới dùng được.',
                      ),
                      value: isPublic,
                      onChanged: (v) => setInner(() => isPublic = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đang hoạt động'),
                      subtitle: const Text('Tắt để tạm dừng mà không cần xoá'),
                      value: isActive,
                      onChanged: (v) => setInner(() => isActive = v),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: () {
                  if (codeCtrl.text.trim().isEmpty) {
                    setInner(() => error = 'Vui lòng nhập mã voucher');
                    return;
                  }
                  if (discountType != 'free_shipping' &&
                      int.tryParse(valueCtrl.text.trim()) == null) {
                    setInner(() => error = 'Vui lòng nhập giá trị giảm hợp lệ');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: Text(existing == null ? 'Tạo' : 'Lưu'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    final data = {
      'code': codeCtrl.text.trim().toUpperCase(),
      'merchant_id': merchantId,
      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'discount_type': discountType,
      'discount_value': discountType == 'free_shipping'
          ? 0
          : (int.tryParse(valueCtrl.text.trim()) ?? 0),
      'max_discount': int.tryParse(maxDiscountCtrl.text.trim()),
      'min_order_amount': int.tryParse(minOrderCtrl.text.trim()) ?? 0,
      'usage_limit': int.tryParse(usageLimitCtrl.text.trim()),
      'usage_limit_per_user':
          int.tryParse(usageLimitPerUserCtrl.text.trim()) ?? 1,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'is_public': isPublic,
      'is_active': isActive,
    };

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await ref.read(adminRepoProvider).createVoucher(data);
      } else {
        await ref.read(adminRepoProvider).updateVoucher(existing.id, data);
      }
      ref.invalidate(vouchersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing == null ? 'Đã tạo voucher' : 'Đã lưu'),
          ),
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

  Future<void> _toggleActive(Voucher v) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateVoucher(v.id, {
        'is_active': !v.isActive,
      });
      ref.invalidate(vouchersProvider);
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

  List<Voucher> _filtered(List<Voucher> all) {
    var list = all;
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list
          .where(
            (v) =>
                v.code.toLowerCase().contains(q) ||
                (v.description?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }
    switch (_statusFilter) {
      case 'Đang chạy':
        list = list.where((v) => v.statusLabel == 'Đang chạy').toList();
      case 'Đã tắt':
        list = list.where((v) => !v.isActive).toList();
      case 'Hết hạn/hết lượt':
        list = list
            .where((v) => v.isActive && (v.isExpired || v.isUsedUp))
            .toList();
    }
    return list;
  }

  Color _statusColor(BuildContext context, Voucher v) {
    final theme = Theme.of(context);
    if (v.statusLabel == 'Đang chạy') return theme.colorScheme.primary;
    if (v.statusLabel == 'Đã tắt') return theme.colorScheme.outline;
    return theme.colorScheme.secondary;
  }

  @override
  Widget build(BuildContext context) {
    final vouchersAsync = ref.watch(vouchersProvider);
    final merchantsAsync = ref.watch(merchantsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _voucherDialog(merchantsAsync.valueOrNull ?? []),
              icon: const Icon(Icons.add),
              label: const Text('Tạo voucher'),
            ),
          ),
        ],
      ),
      body: vouchersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi tải voucher: $e')),
        data: (all) {
          final merchants = merchantsAsync.valueOrNull ?? [];
          String merchantName(String? id) {
            if (id == null) return 'Toàn sàn';
            final m = merchants.where((m) => m.id == id).toList();
            return m.isEmpty ? 'Cửa hàng' : m.first.name;
          }

          final filtered = _filtered(all);
          final running = all.where((v) => v.statusLabel == 'Đang chạy').length;
          final publicCount = all.where((v) => v.isPublic).length;
          final totalUsed = all.fold<int>(0, (sum, v) => sum + v.usedCount);

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900
                      ? 4
                      : constraints.maxWidth > 600
                      ? 2
                      : 1;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2,
                    children: [
                      StatCard(
                        label: 'Tổng voucher',
                        value: '${all.length}',
                        icon: Icons.confirmation_number_outlined,
                      ),
                      StatCard(
                        label: 'Đang chạy',
                        value: '$running',
                        icon: Icons.play_circle_outline,
                        accent: Colors.teal,
                      ),
                      StatCard(
                        label: 'Cho khách chọn',
                        value: '$publicCount',
                        icon: Icons.checklist_outlined,
                        accent: Colors.indigo,
                      ),
                      StatCard(
                        label: 'Tổng lượt đã dùng',
                        value: '$totalUsed',
                        icon: Icons.local_activity_outlined,
                        accent: Colors.orange,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Tìm theo mã hoặc mô tả...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: _statusFilters
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _statusFilter = v ?? 'Tất cả'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          all.isEmpty
                              ? 'Chưa có voucher nào'
                              : 'Không tìm thấy voucher phù hợp',
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (v) => Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      v.code,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                    ),
                                    Chip(
                                      label: Text(v.statusLabel),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: _statusColor(
                                        context,
                                        v,
                                      ).withValues(alpha: 0.12),
                                      labelStyle: TextStyle(
                                        color: _statusColor(context, v),
                                      ),
                                      side: BorderSide.none,
                                    ),
                                    if (v.isPublic)
                                      const Chip(
                                        label: Text('Cho khách chọn'),
                                        visualDensity: VisualDensity.compact,
                                        side: BorderSide.none,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  v.discountLabel(formatVnd: formatVnd),
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (v.description != null &&
                                    v.description!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    v.description!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  '${merchantName(v.merchantId)} · Đơn tối thiểu '
                                  '${formatVnd(v.minOrderAmount)} · Đã dùng '
                                  '${v.usedCount}${v.usageLimit != null ? '/${v.usageLimit}' : ''} lượt'
                                  '${v.usageLimitPerUser > 0 ? ' (tối đa ${v.usageLimitPerUser}/khách)' : ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  v.endsAt == null
                                      ? 'Hiệu lực từ ${formatDate(v.startsAt)}, không giới hạn'
                                      : 'Hiệu lực ${formatDate(v.startsAt)} — ${formatDate(v.endsAt!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (sel) {
                              if (sel == 'edit') {
                                _voucherDialog(merchants, existing: v);
                              }
                              if (sel == 'toggle') _toggleActive(v);
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Sửa'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  v.isActive ? 'Tắt hoạt động' : 'Bật lại',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
