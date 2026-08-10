import '../core/api_client.dart';
import '../models/merchant.dart';

class FavoriteRepository {
  final _api = ApiClient.instance;

  Future<List<Merchant>> list({int limit = 50, int offset = 0}) async {
    final list =
        await _api.get('/favorites', query: {'limit': limit, 'offset': offset})
            as List;
    return list
        .map((e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Set<String>> ids() async {
    final list = await _api.get('/favorites/ids') as List;
    return list.map((e) => e.toString()).toSet();
  }

  Future<void> add(String merchantId) async {
    await _api.post('/favorites', body: {'merchant_id': merchantId});
  }

  Future<void> remove(String merchantId) async {
    await _api.delete('/favorites/$merchantId');
  }
}
