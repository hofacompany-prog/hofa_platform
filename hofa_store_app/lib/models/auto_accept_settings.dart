/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" — admin cấu hình chung cho mọi cửa hàng
/// (web admin, mục Thông số). Store app chỉ đọc để tính trần thời gian chuẩn bị và hiện đúng
/// đếm ngược ở màn nhận đơn (order_offer_screen.dart), không tự chỉnh được.
class AutoAcceptSettings {
  final int autoAcceptDefaultMinutes;
  final int autoAcceptPrepBaseMinutes;
  final int autoAcceptPrepIncrementMinutes;
  final int autoAcceptPrepMaxMinutes;
  final int manualConfirmWindowMinutes;

  AutoAcceptSettings({
    required this.autoAcceptDefaultMinutes,
    required this.autoAcceptPrepBaseMinutes,
    required this.autoAcceptPrepIncrementMinutes,
    required this.autoAcceptPrepMaxMinutes,
    required this.manualConfirmWindowMinutes,
  });

  factory AutoAcceptSettings.fromJson(Map<String, dynamic>? json) => AutoAcceptSettings(
        autoAcceptDefaultMinutes: (json?['auto_accept_default_minutes'] as num?)?.toInt() ?? 8,
        autoAcceptPrepBaseMinutes: (json?['auto_accept_prep_base_minutes'] as num?)?.toInt() ?? 10,
        autoAcceptPrepIncrementMinutes: (json?['auto_accept_prep_increment_minutes'] as num?)?.toInt() ?? 2,
        autoAcceptPrepMaxMinutes: (json?['auto_accept_prep_max_minutes'] as num?)?.toInt() ?? 30,
        manualConfirmWindowMinutes: (json?['manual_confirm_window_minutes'] as num?)?.toInt() ?? 5,
      );
}
