import '../core/api_client.dart';
import '../models/merchant.dart';
import '../models/branch.dart';
import '../models/branch_hours.dart';

class MerchantRepository {
  final _api = ApiClient.instance;

  /// Cửa hàng do user hiện tại sở hữu (bất kể trạng thái), hoặc null nếu chưa có.
  Future<Merchant?> myMerchant() async {
    final list = await _api.get('/merchants/mine') as List;
    if (list.isEmpty) return null;
    return Merchant.fromJson(list.first as Map<String, dynamic>);
  }

  Future<Merchant> createMerchant({
    required String name,
    required String slug,
    String? phone,
    String? logoUrl,
  }) async =>
      Merchant.fromJson(await _api.post('/merchants', body: {
        'name': name,
        'slug': slug,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (logoUrl != null) 'logo_url': logoUrl,
      }) as Map<String, dynamic>);

  Future<Merchant> updateMerchant(String id, Map<String, dynamic> data) async =>
      Merchant.fromJson(await _api.patch('/merchants/$id', body: data) as Map<String, dynamic>);

  Future<List<Branch>> branches(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/branches') as List;
    return list.map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Branch> createBranch({
    required String merchantId,
    required String name,
    required String line1,
    required String province,
    required double latitude,
    required double longitude,
    String? phone,
  }) async =>
      Branch.fromJson(await _api.post('/merchants/$merchantId/branches', body: {
        'name': name,
        'line1': line1,
        'province': province,
        'latitude': latitude,
        'longitude': longitude,
        'is_main': true,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }) as Map<String, dynamic>);

  Future<Branch> toggleBranchOpen(String branchId, bool isOpen) async =>
      Branch.fromJson(await _api.patch('/branches/$branchId/toggle-open', body: {
        'is_open': isOpen,
      }) as Map<String, dynamic>);

  Future<Branch> updateBranch(String branchId, Map<String, dynamic> data) async =>
      Branch.fromJson(await _api.patch('/branches/$branchId', body: data) as Map<String, dynamic>);

  Future<Branch> setAutoAcceptOrders(String branchId, bool value) async =>
      Branch.fromJson(await _api.patch('/branches/$branchId', body: {
        'auto_accept_orders': value,
      }) as Map<String, dynamic>);

  Future<List<BranchHour>> branchHours(String branchId) async {
    final list = await _api.get('/branches/$branchId/hours') as List;
    return list.map((e) => BranchHour.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BranchHour>> setBranchHours(String branchId, List<BranchHour> hours) async {
    final list = await _api.put('/branches/$branchId/hours', body: {
      'hours': hours.map((h) => h.toJson()).toList(),
    }) as List;
    return list.map((e) => BranchHour.fromJson(e as Map<String, dynamic>)).toList();
  }
}
