import '../core/api_client.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/merchant.dart';
import '../models/branch_hours.dart';
import '../models/driver.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/shipping_fee_settings.dart';
import '../models/voucher.dart';
import '../models/order_settings.dart';
import '../models/admin_notification.dart';

/// Gom mọi lời gọi API mà web admin cần. Tất cả endpoint ở đây đều yêu cầu
/// role = 'admin' ở phía server (server/src/utils.js requireRole).
class AdminRepository {
  final _api = ApiClient.instance;

  // ---- Tổng quan ----

  Future<AdminStats> stats() async => AdminStats.fromJson(
    await _api.get('/admin/stats') as Map<String, dynamic>,
  );

  // ---- Người dùng ----

  Future<List<UserProfile>> users({
    String? role,
    String? status,
    String? q,
    int limit = 100,
  }) async {
    final list =
        await _api.get(
              '/admin/users',
              query: {
                'limit': limit,
                if (role != null) 'role': role,
                if (status != null) 'status': status,
                if (q != null && q.isNotEmpty) 'q': q,
              },
            )
            as List;
    return list
        .map((e) => UserProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserProfile> setUserStatus(String userId, String status) async =>
      UserProfile.fromJson(
        await _api.patch(
              '/admin/users/$userId/status',
              body: {'status': status},
            )
            as Map<String, dynamic>,
      );

  Future<UserProfile> setUserRole(String userId, String role) async =>
      UserProfile.fromJson(
        await _api.patch('/admin/users/$userId/role', body: {'role': role})
            as Map<String, dynamic>,
      );

  Future<UserDetail> userDetail(String userId) async => UserDetail.fromJson(
    await _api.get('/admin/users/$userId') as Map<String, dynamic>,
  );

  Future<UserProfile> updateUser(
    String userId,
    Map<String, dynamic> data,
  ) async => UserProfile.fromJson(
    await _api.patch('/admin/users/$userId', body: data)
        as Map<String, dynamic>,
  );

  Future<void> deleteUser(String userId) async {
    await _api.delete('/admin/users/$userId');
  }

  // ---- Cửa hàng ----
  // Admin gọi GET /merchants sẽ thấy MỌI trạng thái (server bỏ lọc status khi role=admin).

  Future<List<Merchant>> merchants({String? q, int limit = 100}) async {
    final list =
        await _api.get(
              '/merchants',
              query: {'limit': limit, if (q != null && q.isNotEmpty) 'q': q},
            )
            as List;
    return list
        .map((e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Merchant> reviewMerchant(
    String id, {
    required bool approve,
    bool certifyStandard = false,
  }) async => Merchant.fromJson(
    await _api.post(
          '/merchants/$id/review',
          body: {'approve': approve, 'certify_standard': certifyStandard},
        )
        as Map<String, dynamic>,
  );

  Future<Merchant> setMerchantPaused(String id, bool paused) async =>
      Merchant.fromJson(
        await _api.patch('/merchants/$id/pause', body: {'paused': paused})
            as Map<String, dynamic>,
      );

  Future<Merchant> setMerchantStatus(String id, String status) async =>
      Merchant.fromJson(
        await _api.patch('/merchants/$id/status', body: {'status': status})
            as Map<String, dynamic>,
      );

  Future<Merchant> merchantDetail(String id) async => Merchant.fromJson(
    await _api.get('/merchants/$id') as Map<String, dynamic>,
  );

  /// [ownerPhone] = SĐT của user có sẵn sẽ làm chủ cửa hàng — bắt buộc khi admin tự tạo hộ.
  Future<Merchant> createMerchant(
    Map<String, dynamic> data, {
    required String ownerPhone,
  }) async => Merchant.fromJson(
    await _api.post('/merchants', body: {...data, 'owner_phone': ownerPhone})
        as Map<String, dynamic>,
  );

  Future<Merchant> updateMerchant(String id, Map<String, dynamic> data) async =>
      Merchant.fromJson(
        await _api.patch('/merchants/$id', body: data) as Map<String, dynamic>,
      );

  Future<void> deleteMerchant(String id) async {
    await _api.delete('/merchants/$id');
  }

  Future<Branch> createBranch(
    String merchantId,
    Map<String, dynamic> data,
  ) async => Branch.fromJson(
    await _api.post('/merchants/$merchantId/branches', body: data)
        as Map<String, dynamic>,
  );

  Future<Branch> updateBranch(
    String branchId,
    Map<String, dynamic> data,
  ) async => Branch.fromJson(
    await _api.patch('/branches/$branchId', body: data) as Map<String, dynamic>,
  );

  Future<List<BranchHour>> branchHours(String branchId) async {
    final list = await _api.get('/branches/$branchId/hours') as List;
    return list
        .map((e) => BranchHour.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Tài xế ----

  Future<List<Driver>> drivers({String? status, int limit = 100}) async {
    final list =
        await _api.get(
              '/admin/drivers',
              query: {'limit': limit, if (status != null) 'status': status},
            )
            as List;
    return list.map((e) => Driver.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Driver> verifyDriver(String id) async => Driver.fromJson(
    await _api.post('/admin/drivers/$id/verify') as Map<String, dynamic>,
  );

  // ---- Đơn hàng ----

  Future<List<Order>> orders({
    String? status,
    String? q,
    int limit = 100,
  }) async {
    final list =
        await _api.get(
              '/admin/orders',
              query: {
                'limit': limit,
                if (status != null) 'status': status,
                if (q != null && q.isNotEmpty) 'q': q,
              },
            )
            as List;
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> order(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> updateOrderStatus(
    String id,
    String status, {
    String? note,
  }) async => Order.fromJson(
    await _api.patch(
          '/orders/$id/status',
          body: {
            'status': status,
            if (note != null && note.isNotEmpty) 'note': note,
          },
        )
        as Map<String, dynamic>,
  );

  /// Xoá thẳng, không chặn theo trạng thái/thanh toán (giai đoạn MVP). Nếu đơn còn bị ràng
  /// buộc khoá ngoại (vd đã có giao dịch thanh toán) thì server trả lỗi cụ thể từ Postgres.
  Future<void> deleteOrder(String id) async {
    await _api.delete('/admin/orders/$id');
  }

  // ---- Danh mục ngành hàng ----

  Future<List<Category>> categories() async {
    final list = await _api.get('/categories') as List;
    return list
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory({
    required String name,
    required String slug,
    String? parentId,
    String? iconUrl,
    String? iconName,
    int? sortOrder,
  }) async => Category.fromJson(
    await _api.post(
          '/categories',
          body: {
            'name': name,
            'slug': slug,
            if (parentId != null) 'parent_id': parentId,
            if (iconUrl != null) 'icon_url': iconUrl,
            if (iconName != null) 'icon_name': iconName,
            if (sortOrder != null) 'sort_order': sortOrder,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Category> updateCategory(String id, Map<String, dynamic> data) async =>
      Category.fromJson(
        await _api.patch('/categories/$id', body: data) as Map<String, dynamic>,
      );

  Future<void> deleteCategory(String id) async {
    await _api.delete('/categories/$id');
  }

  // ---- Phí ship ----

  Future<ShippingFeeSettings> shippingFeeSettings() async {
    final data = await _api.get('/shipping-fee-settings');
    return data == null
        ? ShippingFeeSettings.fallback()
        : ShippingFeeSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<ShippingFeeSettings> updateShippingFeeSettings(
    ShippingFeeSettings settings,
  ) async => ShippingFeeSettings.fromJson(
    await _api.patch('/shipping-fee-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Mã đơn hàng ----

  Future<OrderSettings> orderSettings() async {
    final data = await _api.get('/order-settings');
    return data == null
        ? OrderSettings.fallback()
        : OrderSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<OrderSettings> updateOrderSettings(OrderSettings settings) async =>
      OrderSettings.fromJson(
        await _api.patch('/order-settings', body: settings.toJson())
            as Map<String, dynamic>,
      );

  // ---- Thông báo đẩy ----

  Future<int> notificationAudienceCount({
    required String audienceType,
    List<String>? userIds,
    List<String>? merchantIds,
  }) async {
    final data =
        await _api.get(
              '/admin/notifications/audience',
              query: {
                'audience_type': audienceType,
                if (userIds != null && userIds.isNotEmpty)
                  'user_ids': userIds.join(','),
                if (merchantIds != null && merchantIds.isNotEmpty)
                  'merchant_ids': merchantIds.join(','),
              },
            )
            as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<AdminNotification>> notifications({int limit = 50}) async {
    final list =
        await _api.get('/admin/notifications', query: {'limit': limit}) as List;
    return list
        .map((e) => AdminNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminNotification> sendNotification({
    required String title,
    required String body,
    required String audienceType,
    List<String>? userIds,
    List<String>? merchantIds,
    bool showBadge = false,
  }) async => AdminNotification.fromJson(
    await _api.post(
          '/admin/notifications',
          body: {
            'title': title,
            'body': body,
            'audience_type': audienceType,
            if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
            if (merchantIds != null && merchantIds.isNotEmpty)
              'merchant_ids': merchantIds,
            'show_badge': showBadge,
          },
        )
        as Map<String, dynamic>,
  );

  // ---- Voucher ----
  // GET /vouchers trả về MỌI voucher (kể cả đã tắt/hết hạn) khi gọi với quyền admin.

  Future<List<Voucher>> vouchers({String? merchantId}) async {
    final list =
        await _api.get(
              '/vouchers',
              query: {
                'limit': 200,
                if (merchantId != null) 'merchant_id': merchantId,
              },
            )
            as List;
    return list
        .map((e) => Voucher.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Voucher> createVoucher(Map<String, dynamic> data) async =>
      Voucher.fromJson(
        await _api.post('/vouchers', body: data) as Map<String, dynamic>,
      );

  Future<Voucher> updateVoucher(String id, Map<String, dynamic> data) async =>
      Voucher.fromJson(
        await _api.patch('/vouchers/$id', body: data) as Map<String, dynamic>,
      );

  Future<Voucher> deactivateVoucher(String id) async => Voucher.fromJson(
    await _api.patch('/vouchers/$id/deactivate') as Map<String, dynamic>,
  );

  /// Số voucher tối đa được áp dụng cùng lúc trên 1 đơn — mặc định 1 nếu server chưa có
  /// dòng cấu hình nào.
  Future<int> voucherMaxCount() async {
    final data = await _api.get('/voucher-settings');
    if (data == null) return 1;
    return ((data as Map<String, dynamic>)['max_vouchers_per_order'] as num?)
            ?.toInt() ??
        1;
  }

  Future<int> updateVoucherMaxCount(int maxVouchersPerOrder) async {
    final data =
        await _api.patch(
              '/voucher-settings',
              body: {'max_vouchers_per_order': maxVouchersPerOrder},
            )
            as Map<String, dynamic>;
    return (data['max_vouchers_per_order'] as num?)?.toInt() ?? 1;
  }
}
