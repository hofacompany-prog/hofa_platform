import 'package:flutter/material.dart';

/// 1 lần giao cụ thể trong tuần: thứ (1=T2..7=CN) + giờ giao. Một sản phẩm có thể có
/// nhiều slot cùng thứ (giao nhiều lần trong ngày) hoặc nhiều thứ khác nhau.
class DeliverySlot {
  final int weekday;
  final TimeOfDay time;

  DeliverySlot({required this.weekday, required this.time});

  int get _minutes => time.hour * 60 + time.minute;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'hour': time.hour,
    'minute': time.minute,
  };

  factory DeliverySlot.fromJson(Map<String, dynamic> json) => DeliverySlot(
    weekday: (json['weekday'] as num).toInt(),
    time: TimeOfDay(
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
    ),
  );

  static int compare(DeliverySlot a, DeliverySlot b) {
    if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
    return a._minutes.compareTo(b._minutes);
  }
}
