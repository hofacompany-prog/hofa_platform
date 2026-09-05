/// Cấu hình quét tìm tài xế khi đơn chưa có ai nhận — xem
/// server/src/dispatch.js#sweepDriverSearch. Riêng biệt với DriverAcceptSettings (thời gian
/// thanh trượt "Nhận đơn" SAU KHI đã gán được 1 tài xế cụ thể) — cái này là TRƯỚC khi gán
/// được, lúc quét mà chưa tìm thấy ai cả.
class DriverDispatchSettings {
  final String? id;
  final int rescanIntervalSeconds;
  final int maxRescanAttempts;
  // Công tắc toàn sàn cho nhóm "Tài xế dự phòng" (drivers.is_backup_driver=true, nhận không
  // giới hạn đơn cùng lúc) — tắt thì dù có tài xế đang trong nhóm cũng không được mời, xem
  // hofa-db/98_backup_driver_pool.sql.
  final bool backupPoolEnabled;
  // Bắt đầu tìm tài xế khi thời gian chuẩn bị còn lại bấy nhiêu phút, thay vì đợi tới lúc cửa
  // hàng bấm "Đã làm xong" (ready_for_pickup) — xem hofa-db/105_early_driver_search.sql. Bỏ qua
  // hẳn nếu searchOnConfirm=true.
  final int searchBeforeReadyMinutes;
  // "Tối đa" — tìm tài xế NGAY lúc cửa hàng xác nhận đơn, bỏ qua hẳn searchBeforeReadyMinutes.
  final bool searchOnConfirm;
  // Số đơn tối đa 1 tài xế được chạy cùng lúc (ghép đơn) — 1 = TẮT HẲN tính năng ghép. Xem
  // server/src/batchDispatch.js, hofa-db/107_order_batching.sql.
  final int maxBatchOrders;
  // Số phút tài xế được phép đi thêm (so với chỉ chạy đơn đang có một mình) để nhận thêm 1 đơn
  // ghép — vượt ngưỡng này thì không ghép dù vẫn có 1 thứ tự đi được.
  final int maxBatchDetourMinutes;

  DriverDispatchSettings({
    this.id,
    required this.rescanIntervalSeconds,
    required this.maxRescanAttempts,
    this.backupPoolEnabled = false,
    this.searchBeforeReadyMinutes = 5,
    this.searchOnConfirm = false,
    this.maxBatchOrders = 1,
    this.maxBatchDetourMinutes = 10,
  });

  factory DriverDispatchSettings.fromJson(Map<String, dynamic> json) =>
      DriverDispatchSettings(
        id: json['id'] as String?,
        rescanIntervalSeconds:
            (json['rescan_interval_seconds'] as num?)?.toInt() ?? 60,
        maxRescanAttempts: (json['max_rescan_attempts'] as num?)?.toInt() ?? 10,
        backupPoolEnabled: json['backup_pool_enabled'] as bool? ?? false,
        searchBeforeReadyMinutes:
            (json['search_before_ready_minutes'] as num?)?.toInt() ?? 5,
        searchOnConfirm: json['search_on_confirm'] as bool? ?? false,
        maxBatchOrders: (json['max_batch_orders'] as num?)?.toInt() ?? 1,
        maxBatchDetourMinutes:
            (json['max_batch_detour_minutes'] as num?)?.toInt() ?? 10,
      );

  /// Mặc định dùng khi server chưa có dòng cấu hình nào (chưa từng chạy migration).
  factory DriverDispatchSettings.fallback() => DriverDispatchSettings(
    rescanIntervalSeconds: 60,
    maxRescanAttempts: 10,
    backupPoolEnabled: false,
    searchBeforeReadyMinutes: 5,
    searchOnConfirm: false,
    maxBatchOrders: 1,
    maxBatchDetourMinutes: 10,
  );

  Map<String, dynamic> toJson() => {
    'rescan_interval_seconds': rescanIntervalSeconds,
    'max_rescan_attempts': maxRescanAttempts,
    'backup_pool_enabled': backupPoolEnabled,
    'search_before_ready_minutes': searchBeforeReadyMinutes,
    'search_on_confirm': searchOnConfirm,
    'max_batch_orders': maxBatchOrders,
    'max_batch_detour_minutes': maxBatchDetourMinutes,
  };
}
