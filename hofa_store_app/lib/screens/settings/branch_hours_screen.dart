import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../models/branch_hours.dart';
import '../../repositories/merchant_repository.dart';

class _DayRow {
  bool enabled;
  TimeOfDay open;
  TimeOfDay close;
  _DayRow({required this.enabled, required this.open, required this.close});
}

/// Giờ mở cửa từng ngày trong tuần cho 1 chi nhánh — không bật ngày nào nghĩa là
/// chi nhánh không có lịch cố định cho ngày đó (vẫn có thể mở/đóng thủ công bằng công tắc).
class BranchHoursScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  const BranchHoursScreen({super.key, required this.branchId, required this.branchName});

  @override
  State<BranchHoursScreen> createState() => _BranchHoursScreenState();
}

class _BranchHoursScreenState extends State<BranchHoursScreen> {
  final _repo = MerchantRepository();
  final _days = List.generate(
    7,
    (i) => _DayRow(enabled: false, open: const TimeOfDay(hour: 8, minute: 0), close: const TimeOfDay(hour: 21, minute: 0)),
  );

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hours = await _repo.branchHours(widget.branchId);
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

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(_DayRow row, {required bool isOpen}) async {
    final picked = await showTimePicker(context: context, initialTime: isOpen ? row.open : row.close);
    if (picked == null) return;
    setState(() => isOpen ? row.open = picked : row.close = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final hours = <BranchHour>[
        for (var i = 0; i < 7; i++)
          if (_days[i].enabled) BranchHour(weekday: i, openTime: _fmt(_days[i].open), closeTime: _fmt(_days[i].close)),
      ];
      await _repo.setBranchHours(widget.branchId, hours);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Giờ mở cửa — ${widget.branchName}')),
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
                      for (var i = 0; i < 7; i++)
                        Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(weekdayLabels[i]!, style: const TextStyle(fontWeight: FontWeight.w500)),
                                ),
                                Switch(
                                  value: _days[i].enabled,
                                  onChanged: (v) => setState(() => _days[i].enabled = v),
                                ),
                                if (_days[i].enabled) ...[
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => _pickTime(_days[i], isOpen: true),
                                      child: Text(_fmt(_days[i].open)),
                                    ),
                                  ),
                                  const Text('—'),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => _pickTime(_days[i], isOpen: false),
                                      child: Text(_fmt(_days[i].close)),
                                    ),
                                  ),
                                ] else
                                  const Expanded(child: Text('Đóng cửa', style: TextStyle(color: Colors.black45))),
                              ],
                            ),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
