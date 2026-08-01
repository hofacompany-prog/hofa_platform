import '../core/api_client.dart';
import '../models/branch.dart';
import '../models/merchant.dart';

/// Gom API tra cứu thông tin điểm lấy hàng (chi nhánh + cửa hàng) — tài xế chỉ cần
/// xem, không sửa, nên không cần 1 Repository domain riêng như các app kia.
class PickupRepository {
  final _api = ApiClient.instance;

  Future<Branch> branch(String id) async => Branch.fromJson(await _api.get('/branches/$id') as Map<String, dynamic>);

  Future<Merchant> merchant(String id) async => Merchant.fromJson(await _api.get('/merchants/$id') as Map<String, dynamic>);
}
