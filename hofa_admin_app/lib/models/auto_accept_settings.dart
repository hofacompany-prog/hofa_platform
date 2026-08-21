/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" (branches.auto_accept_orders, store app)
/// và cho bậc thời gian chuẩn bị mặc định/trần ở màn chi tiết đơn (áp dụng mọi đơn "placed").
class AutoAcceptSettings {
  final String? id;
  final int confirmSweepSeconds;
  final int manualConfirmSweepSeconds;
  final int prepTierItems;
  final int prepTierValueVnd;
  final int prepDefaultBaseMinutes;
  final int prepDefaultIncrementMinutes;
  final int prepDefaultMaxMinutes;
  final int prepCeilingBaseMinutes;
  final int prepCeilingIncrementMinutes;
  final int prepCeilingMaxMinutes;
  final int orderReminderIntervalSeconds;

  AutoAcceptSettings({
    this.id,
    required this.confirmSweepSeconds,
    required this.manualConfirmSweepSeconds,
    required this.prepTierItems,
    required this.prepTierValueVnd,
    required this.prepDefaultBaseMinutes,
    required this.prepDefaultIncrementMinutes,
    required this.prepDefaultMaxMinutes,
    required this.prepCeilingBaseMinutes,
    required this.prepCeilingIncrementMinutes,
    required this.prepCeilingMaxMinutes,
    required this.orderReminderIntervalSeconds,
  });

  factory AutoAcceptSettings.fromJson(Map<String, dynamic> json) => AutoAcceptSettings(
        id: json['id'] as String?,
        confirmSweepSeconds: (json['confirm_sweep_seconds'] as num?)?.toInt() ?? 10,
        manualConfirmSweepSeconds: (json['manual_confirm_sweep_seconds'] as num?)?.toInt() ?? 300,
        prepTierItems: (json['prep_tier_items'] as num?)?.toInt() ?? 3,
        prepTierValueVnd: (json['prep_tier_value_vnd'] as num?)?.toInt() ?? 200000,
        prepDefaultBaseMinutes: (json['prep_default_base_minutes'] as num?)?.toInt() ?? 15,
        prepDefaultIncrementMinutes: (json['prep_default_increment_minutes'] as num?)?.toInt() ?? 5,
        prepDefaultMaxMinutes: (json['prep_default_max_minutes'] as num?)?.toInt() ?? 60,
        prepCeilingBaseMinutes: (json['prep_ceiling_base_minutes'] as num?)?.toInt() ?? 30,
        prepCeilingIncrementMinutes: (json['prep_ceiling_increment_minutes'] as num?)?.toInt() ?? 10,
        prepCeilingMaxMinutes: (json['prep_ceiling_max_minutes'] as num?)?.toInt() ?? 120,
        orderReminderIntervalSeconds: (json['order_reminder_interval_seconds'] as num?)?.toInt() ?? 20,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory AutoAcceptSettings.fallback() => AutoAcceptSettings(
        confirmSweepSeconds: 10,
        manualConfirmSweepSeconds: 300,
        prepTierItems: 3,
        prepTierValueVnd: 200000,
        prepDefaultBaseMinutes: 15,
        prepDefaultIncrementMinutes: 5,
        prepDefaultMaxMinutes: 60,
        prepCeilingBaseMinutes: 30,
        prepCeilingIncrementMinutes: 10,
        prepCeilingMaxMinutes: 120,
        orderReminderIntervalSeconds: 20,
      );

  Map<String, dynamic> toJson() => {
        'confirm_sweep_seconds': confirmSweepSeconds,
        'manual_confirm_sweep_seconds': manualConfirmSweepSeconds,
        'prep_tier_items': prepTierItems,
        'prep_tier_value_vnd': prepTierValueVnd,
        'prep_default_base_minutes': prepDefaultBaseMinutes,
        'prep_default_increment_minutes': prepDefaultIncrementMinutes,
        'prep_default_max_minutes': prepDefaultMaxMinutes,
        'prep_ceiling_base_minutes': prepCeilingBaseMinutes,
        'prep_ceiling_increment_minutes': prepCeilingIncrementMinutes,
        'prep_ceiling_max_minutes': prepCeilingMaxMinutes,
        'order_reminder_interval_seconds': orderReminderIntervalSeconds,
      };
}
