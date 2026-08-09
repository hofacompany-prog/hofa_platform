import '../core/api_client.dart';

/// Icon tabbar tuỳ chỉnh do admin chọn (xem hofa_admin_app, màn Danh mục > Icon tabbar) —
/// công khai, không cần đăng nhập, gọi lúc khởi động app.
class NavIconRepository {
  final _api = ApiClient.instance;

  /// Lỗi mạng/parse thì trả về map rỗng — app tự dùng icon Material mặc định, không chặn
  /// khởi động vì thứ này chỉ để trang trí, không phải dữ liệu bắt buộc.
  Future<Map<String, String>> navIcons() async {
    try {
      final list = await _api.get('/nav-icons', query: {'app': 'driver'}) as List;
      return {
        for (final e in list.cast<Map<String, dynamic>>())
          e['tab_key'] as String: e['icon_url'] as String,
      };
    } catch (_) {
      return {};
    }
  }
}
