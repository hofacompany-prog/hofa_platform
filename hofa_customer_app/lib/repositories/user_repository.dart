import '../core/api_client.dart';
import '../models/address.dart';
import '../models/user_profile.dart';

class UserRepository {
  final _api = ApiClient.instance;

  Future<UserProfile> me() async => UserProfile.fromJson(await _api.get('/me') as Map<String, dynamic>);

  Future<UserProfile> syncProfile({required String fullName, required String phone, String? email}) async =>
      UserProfile.fromJson(await _api.post('/me/sync', body: {
        'full_name': fullName,
        'phone': phone,
        if (email != null) 'email': email,
      }) as Map<String, dynamic>);

  Future<UserProfile> updateProfile(Map<String, dynamic> data) async =>
      UserProfile.fromJson(await _api.patch('/me', body: data) as Map<String, dynamic>);

  Future<List<Address>> addresses() async {
    final list = await _api.get('/addresses') as List;
    return list.map((e) => Address.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Address> createAddress(Map<String, dynamic> data) async =>
      Address.fromJson(await _api.post('/addresses', body: data) as Map<String, dynamic>);

  Future<Address> updateAddress(String id, Map<String, dynamic> data) async =>
      Address.fromJson(await _api.patch('/addresses/$id', body: data) as Map<String, dynamic>);

  Future<void> deleteAddress(String id) async {
    await _api.delete('/addresses/$id');
  }

  Future<void> deleteAccount() async {
    await _api.delete('/me');
  }
}
