import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/file_download.dart';
import '../../core/format.dart';
import '../../core/vietqr.dart';
import '../../models/order.dart';
import '../../providers/app_providers.dart';
import '../../widgets/driver_picker_dialog.dart';
import 'orders_list_screen.dart' show orderStatusColor;

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;

  Future<void> _cancel(Order o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đơn hàng?'),
        content: Text('Đơn ${o.orderCode} sẽ bị huỷ và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Không'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Huỷ đơn'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(orderRepoProvider).cancelOrder(o.id, note: 'Khách tự huỷ');
      ref.invalidate(orderDetailProvider(widget.orderId));
      ref.invalidate(myOrdersPagedProvider(ref.read(orderStatusFilterProvider)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Order o) async {
    var rating = 5;
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Đánh giá cửa hàng'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (i) => IconButton(
                      icon: Icon(
                        i < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber.shade700,
                      ),
                      onPressed: () => setInner(() => rating = i + 1),
                    ),
                  ),
                ),
                TextField(
                  controller: commentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nhận xét (không bắt buộc)',
                  ),
                  maxLines: 3,
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
              child: const Text('Gửi'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(reviewRepoProvider)
          .create(
            orderId: o.id,
            targetType: 'merchant',
            targetId: o.merchantId,
            rating: rating,
            comment: commentCtrl.text.trim(),
          );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cảm ơn bạn đã đánh giá!')),
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

  /// Đơn mua hộ cần khách chọn (hoặc chọn lại, sau khi tài xế trước từ chối/hết hạn) tài xế —
  /// xem Order.needsDriverPick. Dùng chung màn chọn với checkout_screen.dart.
  Future<void> _pickDriver(Order o) async {
    final branch = await ref.read(branchDetailProvider(o.branchId).future);
    if (branch.latitude == null || branch.longitude == null || !mounted) return;
    final picked = await showDriverPickerDialog(context, lat: branch.latitude!, lng: branch.longitude!);
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(orderRepoProvider).selectDriver(o.id, picked.id);
      ref.invalidate(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final historyAsync = ref.watch(orderHistoryProvider(widget.orderId));
    final deliveryAsync = ref.watch(orderDeliveryProvider(widget.orderId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/orders'),
        ),
        title: const Text('Chi tiết đơn hàng'),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (o) {
          final color = orderStatusColor(o.status, theme.colorScheme);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              o.orderCode,
                              style: theme.textTheme.titleLarge,
                            ),
                            Chip(
                              label: Text(
                                orderStatusLabels[o.status] ?? o.status,
                              ),
                              backgroundColor: color.withValues(alpha: 0.12),
                              side: BorderSide(
                                color: color.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Đặt lúc ${formatDateTime(o.createdAt)}'),
                        if (o.merchantName != null) Text(o.merchantName!),
                        const Divider(height: 24),
                        Text('Giao đến', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${o.shipRecipientName} · ${o.shipRecipientPhone}',
                        ),
                        Text('${o.shipLine1}, ${o.shipProvince}'),
                      ],
                    ),
                  ),
                ),
                if (o.needsDriverPick) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_search, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cần chọn tài xế để tiếp tục đơn mua hộ',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : () => _pickDriver(o),
                              child: const Text('Chọn tài xế'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Món hàng', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ...o.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item.quantity}× '),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.productName} ${item.variantName ?? ''}',
                                      ),
                                      if (item.toppings.isNotEmpty)
                                        Text(
                                          item.toppings
                                              .map((t) => t.name)
                                              .join(', '),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                Text(formatVnd(item.lineTotal)),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                        _row('Tạm tính', formatVnd(o.subtotal)),
                        _row('Phí giao hàng', formatVnd(o.deliveryFee)),
                        if (o.buyOnBehalfFee > 0)
                          _row('Phí mua hộ', formatVnd(o.buyOnBehalfFee)),
                        if (o.discountAmount > 0)
                          _row('Giảm giá', '-${formatVnd(o.discountAmount)}'),
                        _row('Tổng cộng', formatVnd(o.totalAmount), bold: true),
                        const SizedBox(height: 4),
                        Text(
                          'Thanh toán: ${o.paymentMethod == 'cod' ? 'COD' : 'Chuyển khoản'} · ${o.paymentStatus}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (o.paymentMethod == 'bank_transfer' && o.status == 'pending_payment') ...[
                  const SizedBox(height: 12),
                  _BankTransferQrCard(order: o),
                ],
                deliveryAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, _) => const SizedBox(),
                  data: (delivery) {
                    if (delivery == null || delivery.deliveryOtp == null)
                      return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        elevation: 0,
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.12,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mã giao hàng',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                delivery.deliveryOtp!,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Đọc mã này cho tài xế khi nhận hàng để xác nhận đúng người, đúng đơn.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lịch sử trạng thái',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        historyAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Lỗi: $e'),
                          data: (events) => Column(
                            children: events
                                .map(
                                  (ev) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            orderStatusLabels[ev.status] ??
                                                ev.status,
                                          ),
                                        ),
                                        Text(
                                          formatDateTime(ev.createdAt),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (o.canCancel)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(o),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Huỷ đơn hàng'),
                  ),
                if (o.canReview)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _review(o),
                      icon: const Icon(Icons.star_border),
                      label: const Text('Đánh giá cửa hàng'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        Text(
          value,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      ],
    ),
  );
}

/// Mã VietQR để khách quét chuyển khoản — chỉ hiện cho đơn bank_transfer đang pending_payment.
/// Dựng URL ảnh từ thông tin tài khoản ngân hàng admin cấu hình (bankAccountSettingsProvider),
/// không cần server tạo ảnh riêng — xem core/vietqr.dart.
class _BankTransferQrCard extends ConsumerStatefulWidget {
  final Order order;
  const _BankTransferQrCard({required this.order});

  @override
  ConsumerState<_BankTransferQrCard> createState() => _BankTransferQrCardState();
}

class _BankTransferQrCardState extends ConsumerState<_BankTransferQrCard> {
  bool _downloading = false;

  Future<void> _download(String url, String filename) async {
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Không tải được ảnh QR');
      await FileDownloadService.downloadBytes(res.bodyBytes, filename);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(bankAccountSettingsProvider);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: settingsAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          error: (e, _) => Text('Lỗi: $e'),
          data: (settings) {
            if (!settings.isConfigured) {
              return Text(
                'Cửa hàng chưa cấu hình mã QR chuyển khoản — liên hệ hỗ trợ để được hướng dẫn chuyển khoản.',
                style: theme.textTheme.bodyMedium,
              );
            }
            final qrUrl = buildVietQrUrl(
              bankBin: settings.bankBin!,
              accountNumber: settings.accountNumber!,
              amount: widget.order.totalAmount,
              addInfo: widget.order.orderCode,
              accountName: settings.accountHolderName,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Quét mã để chuyển khoản', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    qrUrl,
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(child: Text('Không tải được ảnh QR')),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('${settings.bankName ?? ''} · ${settings.accountNumber}', style: theme.textTheme.bodyMedium),
                if (settings.accountHolderName != null) Text(settings.accountHolderName!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Số tiền: ${formatVnd(widget.order.totalAmount)} · Nội dung: ${widget.order.orderCode}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _downloading ? null : () => _download(qrUrl, 'vietqr_${widget.order.orderCode}.png'),
                  icon: _downloading
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: const Text('Tải QR về máy'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
