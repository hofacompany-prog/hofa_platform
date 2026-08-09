import '../core/api_client.dart';
import '../models/merchant.dart';
import '../models/merchant_fee_tier.dart';
import '../models/branch.dart';

class MerchantRepository {
  final _api = ApiClient.instance;

  Future<List<Merchant>> merchants({
    String? q,
    String? merchantType,
    int limit = 50,
    int offset = 0,
  }) async {
    final list =
        await _api.get(
              '/merchants',
              query: {
                'limit': limit,
                'offset': offset,
                if (q != null && q.isNotEmpty) 'q': q,
                if (merchantType != null) 'merchant_type': merchantType,
              },
            )
            as List;
    return list
        .map((e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Merchant> merchant(String id) async => Merchant.fromJson(
    await _api.get('/merchants/$id') as Map<String, dynamic>,
  );

  Future<List<Branch>> branches(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/branches') as List;
    return list.map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Branch> branch(String id) async =>
      Branch.fromJson(await _api.get('/branches/$id') as Map<String, dynamic>);

  Future<List<MerchantFeeTier>> feeTiers(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/fee-tiers') as List;
    return list
        .map((e) => MerchantFeeTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
