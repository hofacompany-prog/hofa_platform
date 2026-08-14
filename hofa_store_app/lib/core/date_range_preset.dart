import 'package:intl/intl.dart';

final _yyyyMMdd = DateFormat('yyyy-MM-dd');

/// Khoảng thời gian nhanh cho danh sách đơn hàng — cửa hàng bắt buộc chọn 1 trong 4 (xem
/// orders_list_screen.dart), không còn xem "tất cả" không giới hạn thời gian.
enum DateRangePreset {
  today,
  yesterday,
  week,
  month;

  String get label => switch (this) {
    DateRangePreset.today => 'Hôm nay',
    DateRangePreset.yesterday => 'Hôm qua',
    DateRangePreset.week => 'Tuần qua',
    DateRangePreset.month => 'Tháng qua',
  };

  /// (from, to) dạng YYYY-MM-DD theo ngày hiện tại của máy — khớp cách server tính mốc ngày
  /// theo giờ Việt Nam ở GET /merchants/:merchantId/orders (AT TIME ZONE 'Asia/Ho_Chi_Minh').
  (String, String) toRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DateRangePreset.today => (
        _yyyyMMdd.format(today),
        _yyyyMMdd.format(today),
      ),
      DateRangePreset.yesterday => (
        _yyyyMMdd.format(today.subtract(const Duration(days: 1))),
        _yyyyMMdd.format(today.subtract(const Duration(days: 1))),
      ),
      DateRangePreset.week => (
        _yyyyMMdd.format(today.subtract(const Duration(days: 6))),
        _yyyyMMdd.format(today),
      ),
      DateRangePreset.month => (
        _yyyyMMdd.format(today.subtract(const Duration(days: 29))),
        _yyyyMMdd.format(today),
      ),
    };
  }
}
