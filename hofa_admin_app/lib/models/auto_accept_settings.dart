/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" (branches.auto_accept_orders, store app).
class AutoAcceptSettings {
  final String? id;
  final int autoAcceptDefaultMinutes;
  final int autoAcceptPrepBaseMinutes;
  final int autoAcceptPrepIncrementMinutes;
  final int autoAcceptPrepMaxMinutes;
  final int manualConfirmWindowMinutes;
  final int confirmSweepSeconds;

  AutoAcceptSettings({
    this.id,
    required this.autoAcceptDefaultMinutes,
    required this.autoAcceptPrepBaseMinutes,
    required this.autoAcceptPrepIncrementMinutes,
    required this.autoAcceptPrepMaxMinutes,
    required this.manualConfirmWindowMinutes,
    required this.confirmSweepSeconds,
  });

  factory AutoAcceptSettings.fromJson(Map<String, dynamic> json) => AutoAcceptSettings(
        id: json['id'] as String?,
        autoAcceptDefaultMinutes: (json['auto_accept_default_minutes'] as num?)?.toInt() ?? 8,
        autoAcceptPrepBaseMinutes: (json['auto_accept_prep_base_minutes'] as num?)?.toInt() ?? 10,
        autoAcceptPrepIncrementMinutes: (json['auto_accept_prep_increment_minutes'] as num?)?.toInt() ?? 2,
        autoAcceptPrepMaxMinutes: (json['auto_accept_prep_max_minutes'] as num?)?.toInt() ?? 30,
        manualConfirmWindowMinutes: (json['manual_confirm_window_minutes'] as num?)?.toInt() ?? 5,
        confirmSweepSeconds: (json['confirm_sweep_seconds'] as num?)?.toInt() ?? 10,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory AutoAcceptSettings.fallback() => AutoAcceptSettings(
        autoAcceptDefaultMinutes: 8,
        autoAcceptPrepBaseMinutes: 10,
        autoAcceptPrepIncrementMinutes: 2,
        autoAcceptPrepMaxMinutes: 30,
        manualConfirmWindowMinutes: 5,
        confirmSweepSeconds: 10,
      );

  Map<String, dynamic> toJson() => {
        'auto_accept_default_minutes': autoAcceptDefaultMinutes,
        'auto_accept_prep_base_minutes': autoAcceptPrepBaseMinutes,
        'auto_accept_prep_increment_minutes': autoAcceptPrepIncrementMinutes,
        'auto_accept_prep_max_minutes': autoAcceptPrepMaxMinutes,
        'manual_confirm_window_minutes': manualConfirmWindowMinutes,
        'confirm_sweep_seconds': confirmSweepSeconds,
      };
}
