import '../core/api_client.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/merchant.dart';
import '../models/branch_hours.dart';
import '../models/driver.dart';
import '../models/order.dart';
import '../models/category.dart';

/// Gom mọi lời gọi API mà web admin cần. Tất cả endpoint ở đây đều yêu cầu
/// role = 'admin' ở phía server (server/src/utils.js requireRole).
class AdminRepository {
  final _api = ApiClient.instance;

  // ---- Tổng quan ----

  Future<AdminStats> stats() async =>
      AdminStats.fromJson(await _api.get('/admin/stats') as Map<String, dynamic>);

  // ---- Người dùng ----

  Future<List<UserProfile>> users({String? role, String? status, int limit = 100}) async {
    final list = await _api.get('/admin/users', query: {
      'limit': limit,
      if (role != null) 'role': role,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserProfile> setUserStatus(String userId, String status) async =>
      UserProfile.fromJson(
          await _api.patch('/admin/users/$userId/status', body: {'status': status}) as Map<String, dynamic>);

  Future<UserProfile> setUserRole(String userId, String role) async =>
      UserProfile.fromJson(
          await _api.patch('/admin/users/$userId/role', body: {'role': role}) as Map<String, dynamic>);

  Future<UserDetail> userDetail(String userId) async =>
      UserDetail.fromJson(await _api.get('/admin/users/$userId') as Map<String, dynamic>);

  Future<UserProfile> updateUser(String userId, Map<String, dynamic> data) async =>
      UserProfile.fromJson(await _api.patch('/admin/users/$userId', body: data) as Map<String, dynamic>);

  Future<void> deleteUser(String userId) async {
    await _api.delete('/admin/users/$userId');
  }

  // ---- Cửa hàng ----
  // Admin gọi GET /merchants sẽ thấy MỌI trạng thái (server bỏ lọc status khi role=admin).

  Future<List<Merchant>> merchants({String? q, int limit = 100}) async {
    final list = await _api.get('/merchants', query: {
      'limit': limit,
      if (q != null && q.isNotEmpty) 'q': q,
    }) as List;
    return list.map((e) => Merchant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Merchant> reviewMerchant(String id, {required bool approve, bool certifyStandard = false}) async =>
      Merchant.fromJson(await _api.post('/merchants/$id/review', body: {
        'approve': approve,
        'certify_standard': certifyStandard,
      }) as Map<String, dynamic>);

  Future<Merchant> setMerchantPaused(String id, bool paused) async =>
      Merchant.fromJson(await _api.patch('/merchants/$id/pause', body: {'paused': paused}) as Map<String, dynamic>);

  Future<Merchant> setMerchantStatus(String id, String status) async =>
      Merchant.fromJson(await _api.patch('/merchants/$id/status', body: {'status': status}) as Map<String, dynamic>);

  Future<Merchant> merchantDetail(String id) async =>
      Merchant.fromJson(await _api.get('/merchants/$id') as Map<String, dynamic>);

  /// [ownerPhone] = SĐT của user có sẵn sẽ làm chủ cửa hàng — bắt buộc khi admin tự tạo hộ.
  Future<Merchant> createMerchant(Map<String, dynamic> data, {required String ownerPhone}) async =>
      Merchant.fromJson(await _api.post('/merchants', body: {
        ...data,
        'owner_phone': ownerPhone,
      }) as Map<String, dynamic>);

  Future<Merchant> updateMerchant(String id, Map<String, dynamic> data) async =>
      Merchant.fromJson(await _api.patch('/merchants/$id', body: data) as Map<String, dynamic>);

  Future<void> deleteMerchant(String id) async {
    await _api.delete('/merchants/$id');
  }

  Future<Branch> createBranch(String merchantId, Map<String, dynamic> data) async =>
      Branch.fromJson(await _api.post('/merchants/$merchantId/branches', body: data) as Map<String, dynamic>);

  Future<Branch> updateBranch(String branchId, Map<String, dynamic> data) async =>
      Branch.fromJson(await _api.patch('/branches/$branchId', body: data) as Map<String, dynamic>);

  Future<List<BranchHour>> branchHours(String branchId) async {
    final list = await _api.get('/branches/$branchId/hours') as List;
    return list.map((e) => BranchHour.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- Tài xế ----

  Future<List<Driver>> drivers({String? status, int limit = 100}) async {
    final list = await _api.get('/admin/drivers', query: {
      'limit': limit,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => Driver.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Driver> verifyDriver(String id) async =>
      Driver.fromJson(await _api.post('/admin/drivers/$id/verify') as Map<String, dynamic>);

  // ---- Đơn hàng ----

  Future<List<Order>> orders({String? status, String? q, int limit = 100}) async {
    final list = await _api.get('/admin/orders', query: {
      'limit': limit,
      if (status != null) 'status': status,
      if (q != null && q.isNotEmpty) 'q': q,
    }) as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> order(String id) async => Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> updateOrderStatus(String id, String status, {String? note}) async =>
      Order.fromJson(await _api.patch('/orders/$id/status', body: {
        'status': status,
        if (note != null && note.isNotEmpty) 'note': note,
      }) as Map<String, dynamic>);

  // ---- Danh mục ngành hàng ----

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Category> createCategory({required String name, required String slug, String? parentId}) async =>
      Category.fromJson(await _api.post('/categories', body: {
        'name': name,
        'slug': slug,
        if (parentId != null) 'parent_id': parentId,
      }) as Map<String, dynamic>);

  Future<Category> updateCategory(String id, Map<String, dynamic> data) async =>
      Category.fromJson(await _api.patch('/categories/$id', body: data) as Map<String, dynamic>);
}
