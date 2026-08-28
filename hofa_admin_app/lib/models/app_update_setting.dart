/// Cấu hình ép cập nhật 1 app native (customer/driver/merchant) — xem
/// hofa-db/100_app_update_settings.sql. Build number cài thật (package_info_plus) thấp hơn
/// [minBuildNumber] thì app đó hiện popup KHÔNG có nút bỏ qua, chỉ mở được store đúng nền tảng.
class AppUpdateSetting {
  final String? id;
  final String appScope;
  final int minBuildNumber;
  // Chỉ để HIỂN THỊ trong popup ép cập nhật (vd "2.2.0") — so sánh thật vẫn dựa vào
  // minBuildNumber, xem hofa-db/101_app_update_version_label.sql.
  final String? minVersionLabel;
  final String? iosStoreUrl;
  final String? androidStoreUrl;

  AppUpdateSetting({
    this.id,
    required this.appScope,
    required this.minBuildNumber,
    this.minVersionLabel,
    this.iosStoreUrl,
    this.androidStoreUrl,
  });

  factory AppUpdateSetting.fromJson(Map<String, dynamic> json) =>
      AppUpdateSetting(
        id: json['id'] as String?,
        appScope: json['app_scope'] as String,
        minBuildNumber: (json['min_build_number'] as num?)?.toInt() ?? 1,
        minVersionLabel: json['min_version_label'] as String?,
        iosStoreUrl: json['ios_store_url'] as String?,
        androidStoreUrl: json['android_store_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'min_build_number': minBuildNumber,
    'min_version_label': minVersionLabel,
    'ios_store_url': iosStoreUrl,
    'android_store_url': androidStoreUrl,
  };
}

const appScopeLabels = {
  'customer': 'Khách hàng',
  'driver': 'Tài xế',
  'merchant': 'Cửa hàng',
};
