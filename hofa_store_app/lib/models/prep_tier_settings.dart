/// Bậc thời gian chuẩn bị — admin cấu hình ở "Thông số" (auto_accept_settings), công khai.
/// Bậc tính theo CẢ số phần lẫn giá trị đơn, lấy bậc lớn hơn trong 2 cách tính (xem
/// [tierFor]) — dùng để tính trần +/- ở màn chi tiết đơn (store app). Thời gian chuẩn bị MẶC
/// ĐỊNH đã được chốt sẵn vào Order.defaultPrepMinutes lúc tạo đơn (server, create_order()),
/// không cần model này tính lại.
class PrepTierSettings {
  final int tierItems;
  final int tierValueVnd;
  final int ceilingBaseMinutes;
  final int ceilingIncrementMinutes;
  final int ceilingMaxMinutes;

  PrepTierSettings({
    required this.tierItems,
    required this.tierValueVnd,
    required this.ceilingBaseMinutes,
    required this.ceilingIncrementMinutes,
    required this.ceilingMaxMinutes,
  });

  factory PrepTierSettings.fromJson(Map<String, dynamic> json) => PrepTierSettings(
        tierItems: (json['prep_tier_items'] as num?)?.toInt() ?? 3,
        tierValueVnd: (json['prep_tier_value_vnd'] as num?)?.toInt() ?? 200000,
        ceilingBaseMinutes: (json['prep_ceiling_base_minutes'] as num?)?.toInt() ?? 30,
        ceilingIncrementMinutes: (json['prep_ceiling_increment_minutes'] as num?)?.toInt() ?? 10,
        ceilingMaxMinutes: (json['prep_ceiling_max_minutes'] as num?)?.toInt() ?? 120,
      );

  /// Bậc của đơn = bậc lớn hơn trong 2 cách tính riêng (số phần / giá trị) — đơn nào chạm mốc
  /// nào trước thì tính theo bậc đó.
  int tierFor({required int itemQuantityTotal, required int subtotal}) {
    final tierByItems = tierItems > 0 ? itemQuantityTotal ~/ tierItems : 0;
    final tierByValue = tierValueVnd > 0 ? subtotal ~/ tierValueVnd : 0;
    return tierByItems > tierByValue ? tierByItems : tierByValue;
  }

  /// Trần +/- (phút) cho 1 đơn cụ thể — cửa hàng không được chỉnh vượt quá số này.
  int ceilingFor({required int itemQuantityTotal, required int subtotal}) {
    final tier = tierFor(itemQuantityTotal: itemQuantityTotal, subtotal: subtotal);
    final ceiling = ceilingBaseMinutes + ceilingIncrementMinutes * tier;
    return ceiling < ceilingMaxMinutes ? ceiling : ceilingMaxMinutes;
  }
}
