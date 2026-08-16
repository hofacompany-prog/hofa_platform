import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/branch_hours.dart';
import '../../providers/admin_providers.dart';

class _Window {
  TimeOfDay open;
  TimeOfDay close;
  _Window({required this.open, required this.close});
}

class _DayRow {
  bool enabled;
  List<_Window> windows;
  _DayRow({required this.enabled, required this.windows});
}

/// closed/open24 ưu tiên trước, ghi đè hẳn is_open + branch_hours — custom (theo giờ hoạt
/// động từng ngày, hành vi gốc của màn này) chỉ áp dụng khi không chọn 2 cái trên.
enum _HoursMode { closed, open24, custom }

/// Giờ mở cửa từng ngày trong tuần cho 1 chi nhánh — mỗi ngày cho tối đa 2 khung giờ (vd quán
/// bán sáng + tối), cùng giao diện/luồng dữ liệu (GET/PUT /branches/:id/hours) với màn hình
/// Cửa hàng tự sửa (hofa_store_app/lib/screens/settings/branch_hours_screen.dart): mỗi ngày 1
/// công tắc bật/tắt + các cặp nút chọn giờ mở/đóng, chọn xong khung cuối cùng của 1 ngày hiện
/// luôn danh sách các ngày khác để tick áp dụng cùng (các) khung giờ, đỡ gõ lại 7 lần.
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
      windows: [
        _Window(
          open: const TimeOfDay(hour: 8, minute: 0),
          close: const TimeOfDay(hour: 21, minute: 0),
        ),
      ],
    ),
  );

  static const _maxWindowsPerDay = 2;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Ngày vừa chọn xong CẢ giờ mở lẫn giờ đóng của khung CUỐI CÙNG — hiện danh sách các ngày
  // khác ngay bên dưới để tick chọn áp dụng cùng (các) khung giờ, thay vì hộp thoại riêng.
  int? _copyPromptDayIndex;
  final Set<int> _copySelectedDays = {};

  _HoursMode _mode = _HoursMode.custom;
  bool _modeInitialized = false;

  /// Chỉ chạy ĐÚNG 1 LẦN sau khi cả giờ hoạt động (_load) lẫn is_open của chi nhánh
  /// (merchantDetailProvider) đã có — suy ra đúng chế độ đang áp dụng THẬT SỰ, không phải
  /// đoán mù: is_open=false → đang đóng cửa tay; is_open=true + chưa tick ngày nào → đang mở
  /// 24 giờ (0 dòng branch_hours, xem hofa-db/78_branch_operating_hours_gate.sql); còn lại →
  /// theo giờ hoạt động tuỳ chỉnh như trước.
  void _initModeIfNeeded(bool branchIsOpen) {
    if (_modeInitialized) return;
    _modeInitialized = true;
    if (!branchIsOpen) {
      _mode = _HoursMode.closed;
    } else if (!_days.any((d) => d.enabled)) {
      _mode = _HoursMode.open24;
    } else {
      _mode = _HoursMode.custom;
    }
  }

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
      final byWeekday = <int, List<BranchHour>>{};
      for (final h in hours) {
        (byWeekday[h.weekday] ??= []).add(h);
      }
      byWeekday.forEach((weekday, rows) {
        rows.sort((a, b) => a.openTime.compareTo(b.openTime));
        final windows = <_Window>[];
        for (final h in rows) {
          final open = _parseTime(h.openTime);
          final close = _parseTime(h.closeTime);
          if (open == null || close == null) continue;
          windows.add(_Window(open: open, close: close));
        }
        if (windows.isNotEmpty) {
          _days[weekday] = _DayRow(enabled: true, windows: windows);
        }
      });
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

  Future<void> _pickTime(
    int dayIndex,
    int windowIndex, {
    required bool isOpen,
  }) async {
    final window = _days[dayIndex].windows[windowIndex];
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? window.open : window.close,
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        window.open = picked;
      } else {
        window.close = picked;
      }
      // Chọn xong CẢ giờ mở lẫn giờ đóng của khung CUỐI CÙNG trong ngày (giờ đóng luôn chọn
      // sau) — hiện danh sách các ngày khác ngay bên dưới để tick áp dụng cùng (các) khung
      // giờ, đỡ gõ lại 7 lần.
      if (!isOpen && windowIndex == _days[dayIndex].windows.length - 1) {
        _copyPromptDayIndex = dayIndex;
        _copySelectedDays.clear();
      }
    });
  }

  void _addWindow(int dayIndex) {
    if (_days[dayIndex].windows.length >= _maxWindowsPerDay) return;
    setState(() {
      _days[dayIndex].windows.add(
        _Window(
          open: const TimeOfDay(hour: 17, minute: 0),
          close: const TimeOfDay(hour: 21, minute: 0),
        ),
      );
    });
  }

  void _removeWindow(int dayIndex, int windowIndex) {
    if (_days[dayIndex].windows.length <= 1) return;
    setState(() => _days[dayIndex].windows.removeAt(windowIndex));
  }

  void _applyCopyToOtherDays() {
    if (_copyPromptDayIndex == null || _copySelectedDays.isEmpty) return;
    final source = _days[_copyPromptDayIndex!];
    setState(() {
      for (final i in _copySelectedDays) {
        _days[i] = _DayRow(
          enabled: true,
          windows: source.windows
              .map((w) => _Window(open: w.open, close: w.close))
              .toList(),
        );
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
      final repo = ref.read(adminRepoProvider);
      if (_mode == _HoursMode.closed) {
        // Ưu tiên trước giờ hoạt động — is_open=false, break_until=null (đóng tay vô thời
        // hạn, xem PATCH /branches/:id/toggle-open). KHÔNG đụng branch_hours, giữ nguyên cấu
        // hình theo ngày đang có để mở lại "Theo giờ hoạt động" sau vẫn còn y nguyên.
        await repo.toggleBranchOpen(widget.branchId, isOpen: false);
      } else if (_mode == _HoursMode.open24) {
        // Ưu tiên trước giờ hoạt động — is_open=true + xoá hết branch_hours (0 dòng = mở
        // 24/7, xem hofa-db/78_branch_operating_hours_gate.sql). Không xoá _days ở local
        // state, chỉ không gửi lên, để còn quay lại "Theo giờ hoạt động" mà không mất cấu
        // hình cũ.
        await repo.toggleBranchOpen(widget.branchId, isOpen: true);
        await repo.setBranchHours(widget.branchId, const []);
      } else {
        // Giữ y nguyên hành vi gốc — chỉ thêm đảm bảo is_open=true (phòng trước đó đang ở
        // chế độ "Đóng cửa" rồi đổi sang đây, không thì lưu giờ xong quán vẫn bị đánh dấu
        // đóng).
        await repo.toggleBranchOpen(widget.branchId, isOpen: true);
        final hours = <BranchHour>[
          for (var i = 0; i < 7; i++)
            if (_days[i].enabled)
              for (final w in _days[i].windows)
                BranchHour(
                  weekday: i,
                  openTime: _fmt(w.open),
                  closeTime: _fmt(w.close),
                ),
        ];
        await repo.setBranchHours(widget.branchId, hours);
      }
      ref.invalidate(merchantDetailProvider(widget.merchantId));
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Danh sách các ngày khác trong tuần, hiện ngay dưới ngày [dayIndex] vừa chọn xong giờ —
  /// tick ngày nào thì "Áp dụng" sẽ copy y hệt (các) khung giờ của [dayIndex] sang ngày đó.
  Widget _buildCopyPanel(BuildContext context, int dayIndex) {
    final source = _days[dayIndex];
    final otherDays = [
      for (var i = 0; i < 7; i++)
        if (i != dayIndex) i,
    ];
    final windowsLabel = source.windows
        .map((w) => '${_fmt(w.open)} — ${_fmt(w.close)}')
        .join(', ');
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
              'Áp dụng $windowsLabel cho ngày khác?',
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

  /// 1 dòng khung giờ (nút chọn giờ mở — giờ đóng), kèm nút xoá nếu ngày đó có >1 khung.
  Widget _buildWindowRow(int dayIndex, int windowIndex) {
    final windows = _days[dayIndex].windows;
    final w = windows[windowIndex];
    return Row(
      children: [
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _pickTime(dayIndex, windowIndex, isOpen: true),
            child: Text(_fmt(w.open), style: const TextStyle(fontSize: 13)),
          ),
        ),
        const Text('—', style: TextStyle(fontSize: 12)),
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _pickTime(dayIndex, windowIndex, isOpen: false),
            child: Text(_fmt(w.close), style: const TextStyle(fontSize: 13)),
          ),
        ),
        if (windows.length > 1)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.close),
            tooltip: 'Xoá khung giờ này',
            onPressed: () => _removeWindow(dayIndex, windowIndex),
          )
        else
          const SizedBox(width: 8),
      ],
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
    final branchIsOpen = merchantAsync.maybeWhen(
      data: (m) {
        final branches = m.branches ?? const [];
        for (final b in branches) {
          if (b.id == widget.branchId) return b.isOpen;
        }
        return true;
      },
      orElse: () => true,
    );
    if (!_loading) _initModeIfNeeded(branchIsOpen);

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
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('🌐 Hoạt động 24 giờ'),
                              selected: _mode == _HoursMode.open24,
                              onSelected: (v) => setState(
                                () => _mode = v
                                    ? _HoursMode.open24
                                    : _HoursMode.custom,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('🔒 Đóng cửa'),
                              selected: _mode == _HoursMode.closed,
                              selectedColor: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              onSelected: (v) => setState(
                                () => _mode = v
                                    ? _HoursMode.closed
                                    : _HoursMode.custom,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_mode == _HoursMode.open24)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Cửa hàng sẽ luôn mở, không giới hạn theo khung giờ nào.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        )
                      else if (_mode == _HoursMode.closed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Cửa hàng sẽ đóng cho đến khi bạn đổi lại ở đây.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Theo giờ hoạt động từng ngày bên dưới (tối đa '
                            '$_maxWindowsPerDay khung giờ/ngày):',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ),
                      if (_mode == _HoursMode.custom)
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
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                        onChanged: (v) => setState(
                                          () => _days[i].enabled = v,
                                        ),
                                      ),
                                      if (!_days[i].enabled)
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
                                  if (_days[i].enabled)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 68,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (
                                            var w = 0;
                                            w < _days[i].windows.length;
                                            w++
                                          )
                                            _buildWindowRow(i, w),
                                          if (_days[i].windows.length <
                                              _maxWindowsPerDay)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                onPressed: () =>
                                                    _addWindow(i),
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 14,
                                                ),
                                                label: const Text(
                                                  'Thêm khung giờ',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                            ),
                                        ],
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
