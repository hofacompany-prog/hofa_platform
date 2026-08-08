/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" (branches.auto_accept_orders, store app)
/// và cho bậc thời gian chuẩn bị mặc định/trần ở màn chi tiết đơn (áp dụng mọi đơn "placed").
class AutoAcceptSettings {
  final String? id;
  final int autoAcceptDefaultMinutes;
  final int autoAcceptPrepBaseMinutes;
  final int autoAcceptPrepIncrementMinutes;
  final int autoAcceptPrepMaxMinutes;
  final int manualConfirmWindowMinutes;
  final int confirmSweepSeconds;
  final int prepTierItems;
  final int prepTierValueVnd;
  final int prepDefaultBaseMinutes;
  final int prepDefaultIncrementMinutes;
  final int prepDefaultMaxMinutes;
  final int prepCeilingBaseMinutes;
  final int prepCeilingIncrementMinutes;
  final int prepCeilingMaxMinutes;

  AutoAcceptSettings({
    this.id,
    required this.autoAcceptDefaultMinutes,
    required this.autoAcceptPrepBaseMinutes,
    required this.autoAcceptPrepIncrementMinutes,
    required this.autoAcceptPrepMaxMinutes,
    required this.manualConfirmWindowMinutes,
    required this.confirmSweepSeconds,
    required this.prepTierItems,
    required this.prepTierValueVnd,
    required this.prepDefaultBaseMinutes,
    required this.prepDefaultIncrementMinutes,
    required this.prepDefaultMaxMinutes,
    required this.prepCeilingBaseMinutes,
    required this.prepCeilingIncrementMinutes,
    required this.prepCeilingMaxMinutes,
  });

  factory AutoAcceptSettings.fromJson(Map<String, dynamic> json) => AutoAcceptSettings(
        id: json['id'] as String?,
        autoAcceptDefaultMinutes: (json['auto_accept_default_minutes'] as num?)?.toInt() ?? 8,
        autoAcceptPrepBaseMinutes: (json['auto_accept_prep_base_minutes'] as num?)?.toInt() ?? 10,
        autoAcceptPrepIncrementMinutes: (json['auto_accept_prep_increment_minutes'] as num?)?.toInt() ?? 2,
        autoAcceptPrepMaxMinutes: (json['auto_accept_prep_max_minutes'] as num?)?.toInt() ?? 30,
        manualConfirmWindowMinutes: (json['manual_confirm_window_minutes'] as num?)?.toInt() ?? 5,
        confirmSweepSeconds: (json['confirm_sweep_seconds'] as num?)?.toInt() ?? 10,
        prepTierItems: (json['prep_tier_items'] as num?)?.toInt() ?? 3,
        prepTierValueVnd: (json['prep_tier_value_vnd'] as num?)?.toInt() ?? 200000,
        prepDefaultBaseMinutes: (json['prep_default_base_minutes'] as num?)?.toInt() ?? 15,
        prepDefaultIncrementMinutes: (json['prep_default_increment_minutes'] as num?)?.toInt() ?? 5,
        prepDefaultMaxMinutes: (json['prep_default_max_minutes'] as num?)?.toInt() ?? 60,
        prepCeilingBaseMinutes: (json['prep_ceiling_base_minutes'] as num?)?.toInt() ?? 30,
        prepCeilingIncrementMinutes: (json['prep_ceiling_increment_minutes'] as num?)?.toInt() ?? 10,
        prepCeilingMaxMinutes: (json['prep_ceiling_max_minutes'] as num?)?.toInt() ?? 120,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory AutoAcceptSettings.fallback() => AutoAcceptSettings(
        autoAcceptDefaultMinutes: 8,
        autoAcceptPrepBaseMinutes: 10,
        autoAcceptPrepIncrementMinutes: 2,
        autoAcceptPrepMaxMinutes: 30,
        manualConfirmWindowMinutes: 5,
        confirmSweepSeconds: 10,
        prepTierItems: 3,
        prepTierValueVnd: 200000,
        prepDefaultBaseMinutes: 15,
        prepDefaultIncrementMinutes: 5,
        prepDefaultMaxMinutes: 60,
        prepCeilingBaseMinutes: 30,
        prepCeilingIncrementMinutes: 10,
        prepCeilingMaxMinutes: 120,
      );

  Map<String, dynamic> toJson() => {
        'auto_accept_default_minutes': autoAcceptDefaultMinutes,
        'auto_accept_prep_base_minutes': autoAcceptPrepBaseMinutes,
        'auto_accept_prep_increment_minutes': autoAcceptPrepIncrementMinutes,
        'auto_accept_prep_max_minutes': autoAcceptPrepMaxMinutes,
        'manual_confirm_window_minutes': manualConfirmWindowMinutes,
        'confirm_sweep_seconds': confirmSweepSeconds,
        'prep_tier_items': prepTierItems,
        'prep_tier_value_vnd': prepTierValueVnd,
        'prep_default_base_minutes': prepDefaultBaseMinutes,
        'prep_default_increment_minutes': prepDefaultIncrementMinutes,
        'prep_default_max_minutes': prepDefaultMaxMinutes,
        'prep_ceiling_base_minutes': prepCeilingBaseMinutes,
        'prep_ceiling_increment_minutes': prepCeilingIncrementMinutes,
        'prep_ceiling_max_minutes': prepCeilingMaxMinutes,
      };
}
