import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/preorder_schedule.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/network_image_box.dart';

const _weekdayLabels = [
  (iso: 1, label: 'T2'),
  (iso: 2, label: 'T3'),
  (iso: 3, label: 'T4'),
  (iso: 4, label: 'T5'),
  (iso: 5, label: 'T6'),
  (iso: 6, label: 'T7'),
  (iso: 7, label: 'CN'),
];

/// Giỏ "đặt trước" — cùng dùng chung cartProvider với giỏ hàng thường (giỏ chỉ chứa
/// món của 1 cửa hàng tại 1 thời điểm), chỉ hiển thị khi giỏ đang ở sales_model
/// 'scheduled' (bán sỉ/đặt trước). Khách chọn các ngày giao trong tuần + giờ giao,
/// rồi chọn giao 1 lần (chốt ngày gần nhất) hay giao nhiều lần (lặp lại hàng tuần).
class PreorderScreen extends ConsumerStatefulWidget {
  const PreorderScreen({super.key});

  @override
  ConsumerState<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends ConsumerState<PreorderScreen> {
  final Set<int> _selectedWeekdays = {};
  String _mode = 'once';
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  int _weeks = 1;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  /// Ngày dương lịch gần nhất khớp thứ [isoWeekday] (1=T2..7=CN), tính từ hôm nay —
  /// chỉ để hiển thị trên chip chọn thứ, không phụ thuộc giờ giao đã chọn.
  DateTime _nextDateFor(int isoWeekday) {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    while (d.weekday != isoWeekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  void _goCheckout() {
    if (_selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn ít nhất 1 ngày giao trong tuần')),
      );
      return;
    }
    final schedule = PreorderSchedule(
      weekdays: _selectedWeekdays.toList()..sort(),
      time: _time,
      recurring: _mode == 'recurring',
      weeks: _mode == 'recurring' ? _weeks : 1,
    );
    context.push('/checkout', extra: schedule);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final isPreorderCart = !cart.isEmpty && cart.salesModel == 'scheduled';

    return Scaffold(
      appBar: AppBar(title: const Text('Đặt trước')),
      body: !isPreorderCart
          ? const Center(
              child: Text('Chưa có sản phẩm đặt trước/bán sỉ nào trong giỏ'),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cart.merchantName ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...cart.items.map(
                        (item) => Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                NetworkImageBox(
                                  url: item.productImage,
                                  width: 52,
                                  height: 52,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        item.variantName,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Text(
                                        '${item.quantity} x ${formatVnd(item.unitPrice)}',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatVnd(item.lineTotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => ref
                                          .read(cartProvider.notifier)
                                          .removeItem(item.variantId),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      Text(
                        'Ngày giao trong tuần',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _weekdayLabels
                            .map(
                              (d) => FilterChip(
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _shortDate(_nextDateFor(d.iso)),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    Text(
                                      d.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                selected: _selectedWeekdays.contains(d.iso),
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _selectedWeekdays.add(d.iso);
                                  } else {
                                    _selectedWeekdays.remove(d.iso);
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const Divider(height: 32),
                      Text('Hình thức giao', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Giao 1 lần'),
                            selected: _mode == 'once',
                            onSelected: (_) => setState(() => _mode = 'once'),
                          ),
                          ChoiceChip(
                            label: const Text('Giao nhiều lần'),
                            selected: _mode == 'recurring',
                            onSelected: (_) =>
                                setState(() => _mode = 'recurring'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_outlined),
                        label: Text('Giờ giao: ${_time.format(context)}'),
                        onPressed: _pickTime,
                      ),
                      if (_mode == 'recurring') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Số tuần lặp lại'),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _weeks > 1
                                  ? () => setState(() => _weeks--)
                                  : null,
                            ),
                            Text(
                              '$_weeks',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _weeks < 12
                                  ? () => setState(() => _weeks++)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                      if (_selectedWeekdays.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _mode == 'once'
                              ? 'Giao gần nhất: ${formatDateTime(PreorderSchedule(weekdays: _selectedWeekdays.toList(), time: _time, recurring: false).earliestOccurrence)}'
                              : 'Sẽ tạo ${_selectedWeekdays.length * _weeks} đơn hàng riêng, mỗi ngày đã chọn giao lặp lại trong $_weeks tuần tới',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(
                            alpha: 0.08,
                          ),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng số món'),
                            Text('${cart.itemCount}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Phí ship'),
                            const Text('Miễn phí'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tổng tiền',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              formatVnd(cart.subtotal),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _goCheckout,
                            child: const Text('Đến thanh toán'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
