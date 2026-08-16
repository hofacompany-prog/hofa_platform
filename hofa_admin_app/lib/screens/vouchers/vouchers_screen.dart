import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/vnd_input_formatter.dart';
import '../../models/merchant.dart';
import '../../models/voucher.dart';
import '../../models/voucher_amount_tier.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import '../merchants/merchant_detail_screen.dart' show merchantTypeLabels;
import '../../core/responsive.dart';

const _discountTypeLabels = {
  'percent': 'Phần trăm (%)',
  'fixed': 'Số tiền cố định',
  'free_shipping': 'Miễn phí vận chuyển',
};

const _orderKindLabels = {
  'instant': 'Tức thời',
  'preorder': 'Đặt trước',
  'wholesale': 'Giá sỉ',
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
      text: existing == null
          ? ''
          : existing.discountType == 'percent'
          ? existing.discountValue.toString()
          : VndInputFormatter.display(existing.discountValue),
    );
    final maxDiscountCtrl = TextEditingController(
      text: VndInputFormatter.display(existing?.maxDiscount),
    );
    final minOrderCtrl = TextEditingController(
      text: VndInputFormatter.display(existing?.minOrderAmount ?? 0),
    );
    final usageLimitCtrl = TextEditingController(
      text: existing?.usageLimit?.toString() ?? '',
    );
    final usageLimitPerUserCtrl = TextEditingController(
      text: existing?.usageLimitPerUser.toString() ?? '1',
    );
    final minConcurrentCtrl = TextEditingController(
      text: existing?.minConcurrentOrders?.toString() ?? '',
    );
    String? merchantId = existing?.merchantId;
    String discountType = existing?.discountType ?? 'percent';
    var startsAt = existing?.startsAt ?? DateTime.now();
    var endsAt = existing?.endsAt;
    var isPublic = existing?.isPublic ?? false;
    var isActive = existing?.isActive ?? true;
    final orderKinds = <String>{...?existing?.applicableOrderKinds};
    final merchantTypes = <String>{...?existing?.applicableMerchantTypes};
    var tiers = <VoucherAmountTier>[];
    if (existing != null) {
      try {
        tiers = await ref
            .read(adminRepoProvider)
            .voucherAmountTiers(existing.id);
      } catch (_) {
        // im lặng — mục "Bậc giảm giá" chỉ hiện rỗng, không chặn sửa voucher
      }
    }
    String? error;
    if (!mounted) return;

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

          Future<void> reloadTiers() async {
            if (existing == null) return;
            try {
              final fresh = await ref
                  .read(adminRepoProvider)
                  .voucherAmountTiers(existing.id);
              setInner(() => tiers = fresh);
            } catch (_) {}
          }

          Future<void> tierDialog({VoucherAmountTier? tier}) async {
            final tierMinCtrl = TextEditingController(
              text: VndInputFormatter.display(tier?.minOrderAmount),
            );
            final tierValueCtrl = TextEditingController(
              text: discountType == 'percent'
                  ? tier?.discountValue.toString() ?? ''
                  : VndInputFormatter.display(tier?.discountValue),
            );
            final tierMaxCtrl = TextEditingController(
              text: VndInputFormatter.display(tier?.maxDiscount),
            );
            final tierOk = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(tier == null ? 'Thêm bậc' : 'Sửa bậc'),
                content: SizedBox(
                  width: dialogWidth(context, 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: tierMinCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [VndInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Giá trị đơn tối thiểu (VNĐ)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tierValueCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: discountType == 'percent'
                            ? null
                            : [VndInputFormatter()],
                        decoration: InputDecoration(
                          labelText: discountType == 'percent'
                              ? 'Phần trăm giảm ở bậc này (%)'
                              : 'Số tiền giảm ở bậc này (VNĐ)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tierMaxCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [VndInputFormatter()],
                        decoration: const InputDecoration(
                          labelText:
                              'Giảm tối đa (VNĐ, để trống = không giới hạn)',
                          border: OutlineInputBorder(),
                        ),
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
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            );
            if (tierOk != true || existing == null) return;
            final tierData = {
              'min_order_amount':
                  VndInputFormatter.parse(tierMinCtrl.text) ?? 0,
              'discount_value': discountType == 'percent'
                  ? int.tryParse(tierValueCtrl.text.trim()) ?? 0
                  : VndInputFormatter.parse(tierValueCtrl.text) ?? 0,
              'max_discount': VndInputFormatter.parse(tierMaxCtrl.text),
            };
            try {
              if (tier == null) {
                await ref
                    .read(adminRepoProvider)
                    .createVoucherAmountTier(existing.id, tierData);
              } else {
                await ref
                    .read(adminRepoProvider)
                    .updateVoucherAmountTier(tier.id, tierData);
              }
              await reloadTiers();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
              }
            }
          }

          Future<void> deleteTier(VoucherAmountTier tier) async {
            try {
              await ref
                  .read(adminRepoProvider)
                  .deleteVoucherAmountTier(tier.id);
              await reloadTiers();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
              }
            }
          }

          return AlertDialog(
            title: Text(existing == null ? 'Tạo voucher' : 'Sửa voucher'),
            content: SizedBox(
              width: dialogWidth(context, 480),
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
                        inputFormatters: discountType == 'percent'
                            ? null
                            : [VndInputFormatter()],
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
                        inputFormatters: [VndInputFormatter()],
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
                      inputFormatters: [VndInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Giá trị đơn hàng tối thiểu (VNĐ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Điều kiện áp dụng',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loại đơn (bỏ trống = áp dụng mọi loại)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: _orderKindLabels.entries
                          .map(
                            (e) => FilterChip(
                              label: Text(e.value),
                              selected: orderKinds.contains(e.key),
                              onSelected: (v) => setInner(
                                () => v
                                    ? orderKinds.add(e.key)
                                    : orderKinds.remove(e.key),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loại cửa hàng (bỏ trống = áp dụng mọi loại)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: merchantTypeLabels.entries
                          .map(
                            (e) => FilterChip(
                              label: Text(e.value),
                              selected: merchantTypes.contains(e.key),
                              onSelected: (v) => setInner(
                                () => v
                                    ? merchantTypes.add(e.key)
                                    : merchantTypes.remove(e.key),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: minConcurrentCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText:
                            'Số đơn cùng lúc tối thiểu (để trống = không yêu cầu)',
                        helperText:
                            'Khách phải đang có ít nhất N đơn (tính cả đơn đang đặt) chưa tới lúc tài xế xác nhận đang giao mới dùng được mã.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Bậc giảm giá theo giá trị đơn',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (existing != null && discountType != 'free_shipping')
                          TextButton.icon(
                            onPressed: () => tierDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Thêm bậc'),
                          ),
                      ],
                    ),
                    if (existing == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Lưu voucher trước, sau đó bấm Sửa để thêm bậc giảm giá theo giá trị đơn.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else if (discountType == 'free_shipping')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Không áp dụng bậc cho voucher miễn phí vận chuyển.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else if (tiers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Chưa có bậc nào — dùng nguyên mức giảm cố định ở trên.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      ...(tiers..sort(
                            (a, b) =>
                                a.minOrderAmount.compareTo(b.minOrderAmount),
                          ))
                          .map(
                            (t) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('Từ ${formatVnd(t.minOrderAmount)}'),
                              subtitle: Text(
                                discountType == 'percent'
                                    ? 'Giảm ${t.discountValue}%'
                                          '${t.maxDiscount != null ? ' (tối đa ${formatVnd(t.maxDiscount!)})' : ''}'
                                    : 'Giảm ${formatVnd(t.discountValue)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => tierDialog(tier: t),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                    onPressed: () => deleteTier(t),
                                  ),
                                ],
                              ),
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
                      (discountType == 'percent'
                              ? int.tryParse(valueCtrl.text.trim())
                              : VndInputFormatter.parse(valueCtrl.text)) ==
                          null) {
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
          : discountType == 'percent'
          ? (int.tryParse(valueCtrl.text.trim()) ?? 0)
          : (VndInputFormatter.parse(valueCtrl.text) ?? 0),
      'max_discount': VndInputFormatter.parse(maxDiscountCtrl.text),
      'min_order_amount': VndInputFormatter.parse(minOrderCtrl.text) ?? 0,
      'usage_limit': int.tryParse(usageLimitCtrl.text.trim()),
      'usage_limit_per_user':
          int.tryParse(usageLimitPerUserCtrl.text.trim()) ?? 1,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'is_public': isPublic,
      'is_active': isActive,
      'applicable_order_kinds': orderKinds.isEmpty ? null : orderKinds.toList(),
      'applicable_merchant_types': merchantTypes.isEmpty
          ? null
          : merchantTypes.toList(),
      'min_concurrent_orders': int.tryParse(minConcurrentCtrl.text.trim()),
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
              const _MaxVouchersCard(),
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
                                            color: theme.colorScheme.secondary,
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
                                    if (v.applicableOrderKinds != null)
                                      Chip(
                                        label: Text(
                                          v.applicableOrderKinds!
                                              .map(
                                                (k) => _orderKindLabels[k] ?? k,
                                              )
                                              .join(', '),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        side: BorderSide.none,
                                      ),
                                    if (v.applicableMerchantTypes != null)
                                      Chip(
                                        label: Text(
                                          v.applicableMerchantTypes!
                                              .map(
                                                (t) =>
                                                    merchantTypeLabels[t] ?? t,
                                              )
                                              .join(', '),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        side: BorderSide.none,
                                      ),
                                    if (v.minConcurrentOrders != null)
                                      Chip(
                                        label: Text(
                                          '≥${v.minConcurrentOrders} đơn cùng lúc',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        side: BorderSide.none,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  v.discountLabel(formatVnd: formatVnd),
                                  style: TextStyle(
                                    color: theme.colorScheme.secondary,
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
              const SizedBox(height: 16),
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
            ],
          );
        },
      ),
    );
  }
}

/// Cài đặt số voucher tối đa 1 khách được áp dụng cùng lúc trên 1 đơn — áp dụng cho cả
/// voucher chọn từ danh sách lẫn tự nhập mã ở app khách.
class _MaxVouchersCard extends ConsumerStatefulWidget {
  const _MaxVouchersCard();

  @override
  ConsumerState<_MaxVouchersCard> createState() => _MaxVouchersCardState();
}

class _MaxVouchersCardState extends ConsumerState<_MaxVouchersCard> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  int? _loadedValue;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null || value < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số nguyên từ 1 trở lên')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminRepoProvider).updateVoucherMaxCount(value);
      ref.invalidate(voucherMaxCountProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxCountAsync = ref.watch(voucherMaxCountProvider);
    final theme = Theme.of(context);

    // Điền lại ô nhập mỗi khi tải được giá trị mới từ server (chỉ lần đầu/khi đổi), tránh
    // ghi đè lúc khách đang gõ dở.
    maxCountAsync.whenData((value) {
      if (_loadedValue != value) {
        _loadedValue = value;
        _ctrl.text = value.toString();
      }
    });

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.tune, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cài đặt chung', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Số voucher tối đa khách được áp dụng cùng lúc trên 1 đơn '
                    '(gồm cả voucher chọn từ danh sách và tự nhập mã)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _saving || maxCountAsync.isLoading ? null : _save,
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
    );
  }
}
