class Branch {
  final String id;
  final String merchantId;
  final String name;
  final String? phone;
  final String line1;
  final String? ward;
  final String? district;
  final String province;
  final double latitude;
  final double longitude;
  final bool isMain;
  final bool isOpen;
  final bool autoAcceptOrders;
  final num deliveryRadiusKm;
  // Trạng thái hiệu lực tính live ở server (branch_effective_status(), xem
  // hofa-db/78_branch_operating_hours_gate.sql): 'open' | 'on_break' | 'closed_hours'. Dùng cái
  // này để hiển thị màu/switch thay vì đọc thẳng isOpen — tự đúng khi hết hạn Tạm nghỉ hoặc khi
  // ngoài giờ hoạt động, không cần app tự tính lại múi giờ/branch_hours.
  final String status;
  // Hẹn giờ tự mở lại khi đang "Tạm nghỉ" — null nếu không tạm nghỉ hoặc tạm nghỉ vô thời hạn.
  final DateTime? breakUntil;

  Branch({
    required this.id,
    required this.merchantId,
    required this.name,
    this.phone,
    required this.line1,
    this.ward,
    this.district,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.isMain,
    required this.isOpen,
    required this.autoAcceptOrders,
    required this.deliveryRadiusKm,
    this.status = 'open',
    this.breakUntil,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    line1: json['line1'] as String? ?? '',
    ward: json['ward'] as String?,
    district: json['district'] as String?,
    province: json['province'] as String? ?? '',
    latitude: double.tryParse('${json['latitude']}') ?? 0,
    longitude: double.tryParse('${json['longitude']}') ?? 0,
    isMain: json['is_main'] as bool? ?? false,
    isOpen: json['is_open'] as bool? ?? true,
    autoAcceptOrders: json['auto_accept_orders'] as bool? ?? false,
    deliveryRadiusKm: num.tryParse('${json['delivery_radius_km']}') ?? 5,
    status: json['status'] as String? ?? 'open',
    breakUntil: json['break_until'] != null
        ? DateTime.tryParse(json['break_until'] as String)
        : null,
  );

  String get fullLine => [
    line1,
    ward,
    district,
    province,
  ].where((e) => e != null && e.isNotEmpty).join(', ');
}
