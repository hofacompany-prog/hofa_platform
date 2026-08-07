import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';
import '../merchants/merchant_detail_screen.dart' show merchantTypeLabels;

/// Bảng hoa hồng + thuế suất của MỌI cửa hàng ở 1 chỗ — trước đây phải vào từng cửa hàng
/// riêng lẻ (Cửa hàng > chi tiết > Sửa thông tin) mới sửa được commission_rate/vat_rate/
/// pit_rate, không có cách nào xem tổng quan hay so sánh giữa các cửa hàng. Sửa ở đây gọi lại
/// đúng PATCH /merchants/:id như màn chi tiết, không phải API riêng.
class FinanceSettingsScreen extends ConsumerStatefulWidget {
  const FinanceSettingsScreen({super.key});

  @override
  ConsumerState<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends ConsumerState<FinanceSettingsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _editRates(Merchant m) async {
    final commissionCtrl = TextEditingController(text: m.commissionRate.toString());
    final vatCtrl = TextEditingController(text: m.vatRate.toString());
    final pitCtrl = TextEditingController(text: m.pitRate.toString());
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text('Tài chính — ${m.name}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: commissionCtrl,
                  decoration: const InputDecoration(labelText: 'Hoa hồng (%)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vatCtrl,
                  decoration: const InputDecoration(labelText: 'Thuế GTGT (%)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pitCtrl,
                  decoration: const InputDecoration(labelText: 'Thuế TNCN (%)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mặc định 3% GTGT / 1.5% TNCN theo hộ kinh doanh dịch vụ ăn uống (TT40/2021/TT-BTC) — chỉnh lại nếu cửa hàng đăng ký loại hình khác.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () {
                final commission = num.tryParse(commissionCtrl.text.trim());
                final vat = num.tryParse(vatCtrl.text.trim());
                final pit = num.tryParse(pitCtrl.text.trim());
                if (commission == null || vat == null || pit == null) {
                  setInner(() => error = 'Nhập đúng số cho cả 3 ô');
                  return;
                }
                if ([commission, vat, pit].any((v) => v < 0 || v > 100)) {
                  setInner(() => error = 'Mỗi tỉ lệ phải từ 0 đến 100');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateMerchant(m.id, {
        'commission_rate': num.parse(commissionCtrl.text.trim()),
        'vat_rate': num.parse(vatCtrl.text.trim()),
        'pit_rate': num.parse(pitCtrl.text.trim()),
      });
      ref.invalidate(merchantsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchantsAsync = ref.watch(merchantsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài chính'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(merchantsProvider),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên cửa hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xoá tìm kiếm',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: merchantsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final merchants = all
                    .where((m) => _search.isEmpty || m.name.toLowerCase().contains(_search.toLowerCase()))
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                if (merchants.isEmpty) {
                  return const Center(child: Text('Không có cửa hàng nào khớp tìm kiếm'));
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Cửa hàng')),
                          DataColumn(label: Text('Loại hình')),
                          DataColumn(label: Text('Hoa hồng (%)'), numeric: true),
                          DataColumn(label: Text('Thuế GTGT (%)'), numeric: true),
                          DataColumn(label: Text('Thuế TNCN (%)'), numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: merchants
                            .map(
                              (m) => DataRow(
                                cells: [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 240),
                                      child: Text(
                                        m.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(merchantTypeLabels[m.merchantType] ?? m.merchantType)),
                                  DataCell(Text('${m.commissionRate}')),
                                  DataCell(Text('${m.vatRate}')),
                                  DataCell(Text('${m.pitRate}')),
                                  DataCell(
                                    IconButton(
                                      tooltip: 'Sửa hoa hồng/thuế suất',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: _busy ? null : () => _editRates(m),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
