/// 1 dòng icon tabbar tuỳ chỉnh đã lưu cho 1 tab của 1 app — khớp bảng nav_tab_icons
/// (xem hofa-db/53_nav_tab_icons.sql, GET /nav-icons).
class NavTabIcon {
  final String app;
  final String tabKey;
  final String iconUrl;

  NavTabIcon({required this.app, required this.tabKey, required this.iconUrl});

  factory NavTabIcon.fromJson(Map<String, dynamic> json) => NavTabIcon(
        app: json['app'] as String,
        tabKey: json['tab_key'] as String,
        iconUrl: json['icon_url'] as String,
      );
}
