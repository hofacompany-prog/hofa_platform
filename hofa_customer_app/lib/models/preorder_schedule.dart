import 'package:flutter/material.dart';
import 'delivery_slot.dart';

/// Lịch giao cho đơn đặt trước — gom lại toàn bộ DeliverySlot (thứ + giờ) của mọi món
/// trong giỏ, và chọn giao 1 lần (chốt lần giao gần nhất trong các slot) hay giao nhiều
/// lần (lặp lại hàng tuần trong [weeks] tuần tới, mỗi slot -> 1 đơn riêng mỗi tuần, vì
/// hệ thống hiện chưa có khái niệm đơn lặp định kỳ thật).
class PreorderSchedule {
  final List<DeliverySlot> slots;
  final bool recurring;
  final int weeks;

  const PreorderSchedule({
    required this.slots,
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

  /// Lần giao gần nhất trong các slot đã chọn — dùng cho chế độ "giao 1 lần".
  DateTime get earliestOccurrence => slots
      .map((s) => nextOccurrence(s.weekday, s.time))
      .reduce((a, b) => a.isBefore(b) ? a : b);

  /// Toàn bộ các lần giao — dùng cho chế độ "giao nhiều lần" (mỗi lần = 1 đơn hàng riêng).
  List<DateTime> get occurrences {
    final result = <DateTime>[];
    for (final s in slots) {
      final first = nextOccurrence(s.weekday, s.time);
      for (var i = 0; i < weeks; i++) {
        result.add(first.add(Duration(days: 7 * i)));
      }
    }
    result.sort();
    return result;
  }
}
