import 'package:flutter/material.dart';

/// Lịch giao cho đơn đặt trước — khách chọn các ngày trong tuần (1=T2..7=CN) +
/// giờ giao, và chọn giao 1 lần (chốt ngày gần nhất trong các ngày đã chọn) hay
/// giao nhiều lần (lặp lại hàng tuần trong [weeks] tuần tới, mỗi ngày đã chọn ->
/// 1 đơn riêng cho mỗi tuần, vì hệ thống hiện chưa có khái niệm đơn lặp định kỳ).
class PreorderSchedule {
  final List<int> weekdays;
  final TimeOfDay time;
  final bool recurring;
  final int weeks;

  const PreorderSchedule({
    required this.weekdays,
    required this.time,
    required this.recurring,
    this.weeks = 1,
  });

  static DateTime nextOccurrence(
    int isoWeekday,
    TimeOfDay time, {
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    while (candidate.weekday != isoWeekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Ngày giao gần nhất trong các ngày đã chọn — dùng cho chế độ "giao 1 lần".
  DateTime get earliestOccurrence => weekdays
      .map((w) => nextOccurrence(w, time))
      .reduce((a, b) => a.isBefore(b) ? a : b);

  /// Toàn bộ các lần giao — dùng cho chế độ "giao nhiều lần" (mỗi lần = 1 đơn hàng riêng).
  List<DateTime> get occurrences {
    final result = <DateTime>[];
    for (final w in weekdays) {
      final first = nextOccurrence(w, time);
      for (var i = 0; i < weeks; i++) {
        result.add(first.add(Duration(days: 7 * i)));
      }
    }
    result.sort();
    return result;
  }
}
