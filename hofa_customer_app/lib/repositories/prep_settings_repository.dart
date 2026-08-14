import '../core/api_client.dart';

class PrepSettingsRepository {
  final _api = ApiClient.instance;

  /// Trần thời gian chuẩn bị mặc định (phút), bất kể bậc đơn cao đến đâu — dùng làm mốc an
  /// toàn để chặn khách chọn giờ giao quá gần lúc đặt trước ở màn thanh toán (đơn giao ngay).
  Future<int> prepDefaultMaxMinutes() async {
    final json =
        await _api.get('/auto-accept-settings') as Map<String, dynamic>?;
    return (json?['prep_default_max_minutes'] as num?)?.toInt() ?? 60;
  }
}
