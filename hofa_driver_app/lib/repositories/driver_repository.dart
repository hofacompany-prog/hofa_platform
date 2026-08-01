import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/driver.dart';
import '../models/earnings.dart';

class DriverRepository {
  final _api = ApiClient.instance;

  /// null nếu user chưa có hồ sơ tài xế (chưa đăng ký — role vẫn là 'customer'
  /// nên GET /drivers/me trả FORBIDDEN thay vì 404, coi luôn là "chưa có hồ sơ").
  Future<Driver?> me() async {
    try {
      final json = await _api.get('/drivers/me') as Map<String, dynamic>?;
      return json == null ? null : Driver.fromJson(json);
    } on ApiException catch (e) {
      if (e.code == 'FORBIDDEN') return null;
      rethrow;
    }
  }

  Future<Driver> register({
    required String nationalId,
    required String licenseNo,
    required String vehicleType,
    required String vehiclePlate,
    List<String> documentUrls = const [],
  }) async =>
      Driver.fromJson(await _api.post('/drivers/register', body: {
        'national_id': nationalId,
        'license_no': licenseNo,
        'vehicle_type': vehicleType,
        'vehicle_plate': vehiclePlate,
        if (documentUrls.isNotEmpty) 'document_urls': documentUrls,
      }) as Map<String, dynamic>);

  Future<void> setStatus(String status) async {
    await _api.patch('/drivers/me/status', body: {'status': status});
  }

  Future<void> setAutoAccept(bool autoAccept) async {
    await _api.patch('/drivers/me/auto-accept', body: {'auto_accept': autoAccept});
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    await _api.patch('/drivers/me/location', body: {'latitude': latitude, 'longitude': longitude});
  }

  Future<Earnings> earnings({int limit = 50}) async =>
      Earnings.fromJson(await _api.get('/drivers/me/earnings', query: {'limit': limit}) as Map<String, dynamic>);
}
