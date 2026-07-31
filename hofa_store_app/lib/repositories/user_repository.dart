import '../core/api_client.dart';
import '../models/user_profile.dart';

class UserRepository {
  final _api = ApiClient.instance;

  Future<UserProfile> me() async => UserProfile.fromJson(await _api.get('/me') as Map<String, dynamic>);

  Future<UserProfile> syncProfile({required String fullName, required String phone}) async =>
      UserProfile.fromJson(await _api.post('/me/sync', body: {
        'full_name': fullName,
        'phone': phone,
      }) as Map<String, dynamic>);
}
