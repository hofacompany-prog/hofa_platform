import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../models/auto_accept_settings.dart';
import '../../providers/admin_providers.dart';

/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" (branches.auto_accept_orders, store app) —
/// không cài riêng theo từng cửa hàng. Ở màn chi tiết đơn (store app), đơn "placed" luôn hiện
/// thanh trượt xác nhận với dải màu chạy — BẬT: chạy confirm_sweep_seconds giây, hết giờ tự
/// XÁC NHẬN hộ. TẮT: chạy manual_confirm_sweep_seconds giây (màu khác), hết giờ tự HUỶ đơn và
/// tự đóng cửa chi nhánh — coi như cửa hàng không theo dõi đơn. Cả 2 xử lý hoàn toàn phía
/// client (store app), không có vòng quét nền phía server.
class AutoAcceptSettingsScreen extends ConsumerStatefulWidget {
  const AutoAcceptSettingsScreen({super.key});

  @override
  ConsumerState<AutoAcceptSettingsScreen> createState() => _AutoAcceptSettingsScreenState();
}

class _AutoAcceptSettingsScreenState extends ConsumerState<AutoAcceptSettingsScreen> {
  final _confirmSweepCtrl = TextEditingController();
  final _manualConfirmSweepCtrl = TextEditingController();
  final _tierItemsCtrl = TextEditingController();
  final _tierValueCtrl = TextEditingController();
  final _prepDefaultBaseCtrl = TextEditingController();
  final _prepDefaultIncrementCtrl = TextEditingController();
  final _prepDefaultMaxCtrl = TextEditingController();
  final _prepCeilingBaseCtrl = TextEditingController();
  final _prepCeilingIncrementCtrl = TextEditingController();
  final _prepCeilingMaxCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _confirmSweepCtrl.dispose();
    _manualConfirmSweepCtrl.dispose();
    _tierItemsCtrl.dispose();
    _tierValueCtrl.dispose();
    _prepDefaultBaseCtrl.dispose();
    _prepDefaultIncrementCtrl.dispose();
    _prepDefaultMaxCtrl.dispose();
    _prepCeilingBaseCtrl.dispose();
    _prepCeilingIncrementCtrl.dispose();
    _prepCeilingMaxCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(AutoAcceptSettings s) {
    _confirmSweepCtrl.text = s.confirmSweepSeconds.toString();
    _manualConfirmSweepCtrl.text = s.manualConfirmSweepSeconds.toString();
    _tierItemsCtrl.text = s.prepTierItems.toString();
    _tierValueCtrl.text = s.prepTierValueVnd.toString();
    _prepDefaultBaseCtrl.text = s.prepDefaultBaseMinutes.toString();
    _prepDefaultIncrementCtrl.text = s.prepDefaultIncrementMinutes.toString();
    _prepDefaultMaxCtrl.text = s.prepDefaultMaxMinutes.toString();
    _prepCeilingBaseCtrl.text = s.prepCeilingBaseMinutes.toString();
    _prepCeilingIncrementCtrl.text = s.prepCeilingIncrementMinutes.toString();
    _prepCeilingMaxCtrl.text = s.prepCeilingMaxMinutes.toString();
  }

  Future<void> _save(String? id) async {
    final confirmSweep = int.tryParse(_confirmSweepCtrl.text.trim());
    final manualConfirmSweep = int.tryParse(_manualConfirmSweepCtrl.text.trim());
    if (confirmSweep == null || confirmSweep <= 0) {
      _showError('Thời gian thanh chạy màu (khi bật) không hợp lệ');
      return;
    }
    if (manualConfirmSweep == null || manualConfirmSweep <= 0) {
      _showError('Thời gian thanh chạy màu (khi tắt) không hợp lệ');
      return;
    }
    final tierItems = int.tryParse(_tierItemsCtrl.text.trim());
    final tierValue = int.tryParse(_tierValueCtrl.text.trim());
    final prepDefaultBase = int.tryParse(_prepDefaultBaseCtrl.text.trim());
    final prepDefaultIncrement = int.tryParse(_prepDefaultIncrementCtrl.text.trim());
    final prepDefaultMax = int.tryParse(_prepDefaultMaxCtrl.text.trim());
    final prepCeilingBase = int.tryParse(_prepCeilingBaseCtrl.text.trim());
    final prepCeilingIncrement = int.tryParse(_prepCeilingIncrementCtrl.text.trim());
    final prepCeilingMax = int.tryParse(_prepCeilingMaxCtrl.text.trim());
    if (tierItems == null || tierItems <= 0) {
      _showError('Mốc bậc theo số phần không hợp lệ');
      return;
    }
    if (tierValue == null || tierValue <= 0) {
      _showError('Mốc bậc theo giá trị đơn không hợp lệ');
      return;
    }
    if (prepDefaultBase == null || prepDefaultBase <= 0) {
      _showError('Thời gian chuẩn bị mặc định ở bậc 0 không hợp lệ');
      return;
    }
    if (prepDefaultIncrement == null || prepDefaultIncrement < 0) {
      _showError('Số phút cộng thêm mỗi bậc (mặc định) không hợp lệ');
      return;
    }
    if (prepDefaultMax == null || prepDefaultMax < prepDefaultBase) {
      _showError('Trần thời gian chuẩn bị mặc định phải lớn hơn hoặc bằng số phút ở bậc 0');
      return;
    }
    if (prepCeilingBase == null || prepCeilingBase < prepDefaultBase) {
      _showError('Số phút tối đa cửa hàng chỉnh được ở bậc 0 phải lớn hơn hoặc bằng thời gian mặc định ở bậc 0');
      return;
    }
    if (prepCeilingIncrement == null || prepCeilingIncrement < 0) {
      _showError('Số phút cộng thêm mỗi bậc (trần) không hợp lệ');
      return;
    }
    if (prepCeilingMax == null || prepCeilingMax < prepCeilingBase || prepCeilingMax < prepDefaultMax) {
      _showError('Trần tuyệt đối phải lớn hơn hoặc bằng cả trần ở bậc 0 lẫn trần thời gian chuẩn bị mặc định');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref.read(adminRepoProvider).updateAutoAcceptSettings(
            AutoAcceptSettings(
              id: id,
              confirmSweepSeconds: confirmSweep,
              manualConfirmSweepSeconds: manualConfirmSweep,
              prepTierItems: tierItems,
              prepTierValueVnd: tierValue,
              prepDefaultBaseMinutes: prepDefaultBase,
              prepDefaultIncrementMinutes: prepDefaultIncrement,
              prepDefaultMaxMinutes: prepDefaultMax,
              prepCeilingBaseMinutes: prepCeilingBase,
              prepCeilingIncrementMinutes: prepCeilingIncrement,
              prepCeilingMaxMinutes: prepCeilingMax,
            ),
          );
      ref.invalidate(autoAcceptSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông số')),
        );
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bảng bậc tính live từ nội dung đang gõ trong ô (kể cả chưa lưu) — giúp hình dung ngay
  /// từng bậc dịch ra bao nhiêu phút, không cần tự nhẩm base + tăng×bậc trong đầu. Dừng sớm
  /// (thay vì luôn liệt kê đủ 11 bậc) ngay khi cả 2 cột "Mặc định" và "Trần +/-" đã chạm trần —
  /// các bậc sau đó cho ra số giống hệt nhau, liệt kê thêm chỉ gây rối mắt.
  List<_TierPreviewRow> _previewRows() {
    final tierItems = int.tryParse(_tierItemsCtrl.text.trim()) ?? 0;
    final tierValue = int.tryParse(_tierValueCtrl.text.trim()) ?? 0;
    if (tierItems <= 0 || tierValue <= 0) return const [];
    final defBase = int.tryParse(_prepDefaultBaseCtrl.text.trim()) ?? 0;
    final defInc = int.tryParse(_prepDefaultIncrementCtrl.text.trim()) ?? 0;
    final defMax = int.tryParse(_prepDefaultMaxCtrl.text.trim()) ?? 0;
    final ceilBase = int.tryParse(_prepCeilingBaseCtrl.text.trim()) ?? 0;
    final ceilInc = int.tryParse(_prepCeilingIncrementCtrl.text.trim()) ?? 0;
    final ceilMax = int.tryParse(_prepCeilingMaxCtrl.text.trim()) ?? 0;

    final rows = <_TierPreviewRow>[];
    for (var tier = 0; tier <= 10; tier++) {
      final rawDefault = defBase + defInc * tier;
      final rawCeiling = ceilBase + ceilInc * tier;
      final defaultMinutes = defMax > 0 && rawDefault > defMax ? defMax : rawDefault;
      final ceilingMinutes = ceilMax > 0 && rawCeiling > ceilMax ? ceilMax : rawCeiling;
      rows.add(_TierPreviewRow(
        tier: tier,
        fromItems: tier * tierItems,
        fromValue: tier * tierValue,
        defaultMinutes: defaultMinutes,
        ceilingMinutes: ceilingMinutes,
      ));
      final defSaturated = defMax > 0 && defaultMinutes >= defMax;
      final ceilSaturated = ceilMax > 0 && ceilingMinutes >= ceilMax;
      if (tier > 0 && defSaturated && ceilSaturated) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(autoAcceptSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thông số')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) {
          if (!_initialized) {
            _fillFrom(settings);
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Áp dụng cho toàn sàn — điều khiển hành vi công tắc "Tự động nhận đơn" ở '
                      'Cài đặt chi nhánh trong app cửa hàng, không cài riêng theo từng cửa hàng.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Khi bật "Tự động nhận đơn"',
                      child: _NumberField(
                        controller: _confirmSweepCtrl,
                        label: 'Thời gian thanh chạy màu để xác nhận (giây)',
                        helper: 'Ở màn chi tiết đơn, dải màu chạy trên thanh trượt xác nhận trong bấy nhiêu '
                            'giây. Hết giờ mà cửa hàng chưa trượt, hệ thống tự chốt số phút đang hiện trên bộ '
                            'đếm +/- làm thời gian chuẩn bị và tự XÁC NHẬN đơn.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Khi tắt "Tự động nhận đơn"',
                      child: _NumberField(
                        controller: _manualConfirmSweepCtrl,
                        label: 'Thời gian thanh chạy màu để xác nhận (giây)',
                        helper: 'Cùng vị trí thanh trượt như trên nhưng đổi màu khác. Hết giờ mà cửa hàng chưa '
                            'trượt, hệ thống tự HUỶ đơn và tự đóng cửa chi nhánh — coi như cửa hàng không '
                            'theo dõi đơn. Nên đặt dài hơn hẳn thời gian ở trên (mặc định 300 giây = 5 phút).',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Mốc bậc thời gian chuẩn bị (dùng chung)',
                      child: Column(
                        children: [
                          Text(
                            'Đơn nào chạm mốc SỐ PHẦN hay GIÁ TRỊ trước thì tính theo bậc đó (lấy bậc lớn '
                            'hơn trong 2 cách tính). Dùng chung cho cả thời gian chuẩn bị mặc định lẫn trần '
                            '+/- bên dưới.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _tierItemsCtrl,
                            label: 'Cứ mỗi bao nhiêu phần thì +1 bậc (số phần)',
                            helper: 'Số phần = tổng số lượng món trong đơn (không phân biệt loại món).',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _tierValueCtrl,
                            label: 'Cứ mỗi bao nhiêu đồng thì +1 bậc (giá trị đơn)',
                            helper: 'Tính theo tổng tiền món (subtotal), chưa gồm phí ship.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Thời gian chuẩn bị mặc định (theo bậc)',
                      child: Column(
                        children: [
                          Text(
                            'Số phút hiện sẵn ở màn chi tiết đơn (store app) khi đơn vừa vào — chốt luôn lúc '
                            'tạo đơn, không đổi dù sau đó bạn có sửa lại Thông số.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultBaseCtrl,
                            label: 'Thời gian chuẩn bị mặc định ở bậc 0 (phút)',
                            helper: 'Áp dụng cho đơn chưa chạm mốc bậc nào ở trên.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultIncrementCtrl,
                            label: 'Cộng thêm mỗi bậc (phút)',
                            helper: 'Mỗi bậc vượt qua, cộng thêm bấy nhiêu phút vào thời gian chuẩn bị mặc định.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultMaxCtrl,
                            label: 'Trần thời gian chuẩn bị mặc định (phút)',
                            helper: 'Trần tuyệt đối, bất kể bậc cao đến đâu.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Thời gian tối đa cửa hàng được chỉnh (theo bậc)',
                      child: Column(
                        children: [
                          Text(
                            'Giới hạn trên của nút +/- ở màn chi tiết đơn — cửa hàng không bấm + vượt quá '
                            'số này, dù đang ở trạng thái mặc định hay đã tự chỉnh.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingBaseCtrl,
                            label: 'Trần +/- ở bậc 0 (phút)',
                            helper: 'Phải lớn hơn hoặc bằng thời gian chuẩn bị mặc định ở bậc 0.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingIncrementCtrl,
                            label: 'Cộng thêm mỗi bậc (phút)',
                            helper: 'Mỗi bậc vượt qua, cộng thêm bấy nhiêu phút vào trần +/-.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingMaxCtrl,
                            label: 'Trần +/- tuyệt đối (phút)',
                            helper: 'Trần tuyệt đối, bất kể bậc cao đến đâu.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _tierItemsCtrl,
                        _tierValueCtrl,
                        _prepDefaultBaseCtrl,
                        _prepDefaultIncrementCtrl,
                        _prepDefaultMaxCtrl,
                        _prepCeilingBaseCtrl,
                        _prepCeilingIncrementCtrl,
                        _prepCeilingMaxCtrl,
                      ]),
                      builder: (context, _) => _TierPreviewTable(rows: _previewRows()),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(settings.id),
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String helper;
  const _NumberField({required this.controller, required this.label, required this.helper});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, border: const OutlineInputBorder()),
    );
  }
}

class _TierPreviewRow {
  final int tier;
  final int fromItems;
  final int fromValue;
  final int defaultMinutes;
  final int ceilingMinutes;
  const _TierPreviewRow({
    required this.tier,
    required this.fromItems,
    required this.fromValue,
    required this.defaultMinutes,
    required this.ceilingMinutes,
  });
}

/// Bảng xem trước — hiện ngay dưới 3 mục cấu hình bậc, cập nhật live theo nội dung đang gõ.
class _TierPreviewTable extends StatelessWidget {
  final List<_TierPreviewRow> rows;
  const _TierPreviewTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return _SectionCard(
        title: 'Xem trước theo bậc',
        child: Text(
          'Điền đủ 2 mốc bậc ở trên để xem bảng bậc thực tế.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    return _SectionCard(
      title: 'Xem trước theo bậc',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cập nhật ngay theo số bạn đang gõ (kể cả chưa lưu) — mỗi dòng là 1 bậc, cho biết đơn '
            'đạt tới đó thì thời gian mặc định/trần +/- là bao nhiêu.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder(horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant)),
            columnWidths: const {
              0: FlexColumnWidth(0.6),
              1: FlexColumnWidth(1.1),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(1.2),
            },
            children: [
              TableRow(
                children: [
                  _headerCell(theme, 'Bậc'),
                  _headerCell(theme, '≥ Phần'),
                  _headerCell(theme, '≥ Giá trị'),
                  _headerCell(theme, 'Mặc định'),
                  _headerCell(theme, 'Trần +/-'),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    _cell(theme, '${row.tier}'),
                    _cell(theme, '${row.fromItems}'),
                    _cell(theme, formatVnd(row.fromValue)),
                    _cell(theme, '${row.defaultMinutes} phút'),
                    _cell(theme, '${row.ceilingMinutes} phút'),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCell(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(text, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _cell(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(text, style: theme.textTheme.bodyMedium),
      );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
