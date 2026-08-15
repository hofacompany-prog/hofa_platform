import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/branch_hours.dart';
import '../../providers/admin_providers.dart';

class _DayRow {
  bool enabled;
  TimeOfDay open;
  TimeOfDay close;
  _DayRow({required this.enabled, required this.open, required this.close});
}

/// Giờ mở cửa từng ngày trong tuần cho 1 chi nhánh — cùng giao diện/luồng dữ liệu (GET/PUT
/// /branches/:id/hours) với màn hình Cửa hàng tự sửa
/// (hofa_store_app/lib/screens/settings/branch_hours_screen.dart): mỗi ngày 1 công tắc bật/tắt +
/// 2 nút chọn giờ mở/đóng riêng, chọn xong 1 ngày hiện luôn danh sách các ngày khác để tick áp
/// dụng cùng khung giờ, đỡ gõ lại 7 lần.
class BranchHoursScreen extends ConsumerStatefulWidget {
  final String merchantId;
  final String branchId;
  const BranchHoursScreen({
    super.key,
    required this.merchantId,
    required this.branchId,
  });

  @override
  ConsumerState<BranchHoursScreen> createState() => _BranchHoursScreenState();
}

class _BranchHoursScreenState extends ConsumerState<BranchHoursScreen> {
  final _days = List.generate(
    7,
    (i) => _DayRow(
      enabled: false,
      open: const TimeOfDay(hour: 8, minute: 0),
      close: const TimeOfDay(hour: 21, minute: 0),
    ),
  );

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Ngày vừa chọn xong CẢ giờ mở lẫn giờ đóng — hiện danh sách các ngày khác ngay bên dưới để
  // tick chọn áp dụng cùng khung giờ, thay vì hộp thoại riêng.
  int? _copyPromptDayIndex;
  final Set<int> _copySelectedDays = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hours = await ref
          .read(adminRepoProvider)
          .branchHours(widget.branchId);
      for (final h in hours) {
        final open = _parseTime(h.openTime);
        final close = _parseTime(h.closeTime);
        if (open == null || close == null) continue;
        _days[h.weekday] = _DayRow(enabled: true, open: open, close: close);
      }
    } catch (e) {
      _error = 'Không tải được giờ mở cửa: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay? _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(int dayIndex, {required bool isOpen}) async {
    final row = _days[dayIndex];
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? row.open : row.close,
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        row.open = picked;
      } else {
        row.close = picked;
      }
      // Chọn xong CẢ giờ mở lẫn giờ đóng cho 1 ngày (giờ đóng luôn chọn sau) — hiện danh sách
      // các ngày khác ngay bên dưới ngày này để tick áp dụng cùng khung giờ, đỡ gõ lại 7 lần.
      if (!isOpen) {
        _copyPromptDayIndex = dayIndex;
        _copySelectedDays.clear();
      }
    });
  }

  void _applyCopyToOtherDays() {
    if (_copyPromptDayIndex == null || _copySelectedDays.isEmpty) return;
    final source = _days[_copyPromptDayIndex!];
    setState(() {
      for (final i in _copySelectedDays) {
        _days[i] = _DayRow(enabled: true, open: source.open, close: source.close);
      }
      _copyPromptDayIndex = null;
      _copySelectedDays.clear();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final hours = <BranchHour>[
        for (var i = 0; i < 7; i++)
          if (_days[i].enabled)
            BranchHour(
              weekday: i,
              openTime: _fmt(_days[i].open),
              closeTime: _fmt(_days[i].close),
            ),
      ];
      await ref.read(adminRepoProvider).setBranchHours(widget.branchId, hours);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Danh sách các ngày khác trong tuần, hiện ngay dưới ngày [dayIndex] vừa chọn xong giờ —
  /// tick ngày nào thì "Áp dụng" sẽ copy y hệt khung giờ của [dayIndex] sang ngày đó.
  Widget _buildCopyPanel(BuildContext context, int dayIndex) {
    final source = _days[dayIndex];
    final otherDays = [
      for (var i = 0; i < 7; i++)
        if (i != dayIndex) i,
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Áp dụng ${_fmt(source.open)} — ${_fmt(source.close)} cho ngày khác?',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            Wrap(
              children: [
                for (final i in otherDays)
                  SizedBox(
                    width: 120,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        weekdayLabels[i]!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: _copySelectedDays.contains(i),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _copySelectedDays.add(i);
                        } else {
                          _copySelectedDays.remove(i);
                        }
                      }),
                    ),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _copyPromptDayIndex = null;
                      _copySelectedDays.clear();
                    }),
                    child: const Text('Bỏ qua'),
                  ),
                  FilledButton(
                    onPressed: _copySelectedDays.isEmpty
                        ? null
                        : _applyCopyToOtherDays,
                    child: const Text('Áp dụng'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchantAsync = ref.watch(merchantDetailProvider(widget.merchantId));
    final branchName = merchantAsync.maybeWhen(
      data: (m) {
        final branches = m.branches ?? const [];
        for (final b in branches) {
          if (b.id == widget.branchId) return b.name;
        }
        return null;
      },
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Giờ mở cửa${branchName != null ? ' — $branchName' : ''}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 6),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 68,
                                  child: Text(
                                    weekdayLabels[i]!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Switch(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  value: _days[i].enabled,
                                  onChanged: (v) =>
                                      setState(() => _days[i].enabled = v),
                                ),
                                if (_days[i].enabled) ...[
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          _pickTime(i, isOpen: true),
                                      child: Text(
                                        _fmt(_days[i].open),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    '—',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          _pickTime(i, isOpen: false),
                                      child: Text(
                                        _fmt(_days[i].close),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ] else
                                  const Expanded(
                                    child: Text(
                                      'Đóng cửa',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (_copyPromptDayIndex == i)
                          _buildCopyPanel(context, i),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lưu'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
