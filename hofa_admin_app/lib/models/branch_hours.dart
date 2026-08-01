/// Giờ mở cửa 1 ngày trong tuần. weekday: 0 = Chủ nhật ... 6 = Thứ bảy (khớp branch_hours.weekday).
class BranchHour {
  final int weekday;
  final String openTime; // 'HH:mm' hoặc 'HH:mm:ss'
  final String closeTime;

  BranchHour({required this.weekday, required this.openTime, required this.closeTime});

  factory BranchHour.fromJson(Map<String, dynamic> json) => BranchHour(
        weekday: json['weekday'] as int,
        openTime: (json['open_time'] as String).substring(0, 5),
        closeTime: (json['close_time'] as String).substring(0, 5),
      );
}

const weekdayLabels = {
  0: 'Chủ nhật',
  1: 'Thứ hai',
  2: 'Thứ ba',
  3: 'Thứ tư',
  4: 'Thứ năm',
  5: 'Thứ sáu',
  6: 'Thứ bảy',
};
