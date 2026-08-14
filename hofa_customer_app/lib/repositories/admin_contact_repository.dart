import '../core/api_client.dart';
import '../models/admin_contact_settings.dart';

class AdminContactRepository {
  final _api = ApiClient.instance;

  Future<AdminContactSettings> get() async {
    final data = await _api.get('/admin-contact-settings');
    return data == null
        ? AdminContactSettings.empty()
        : AdminContactSettings.fromJson(data as Map<String, dynamic>);
  }
}
