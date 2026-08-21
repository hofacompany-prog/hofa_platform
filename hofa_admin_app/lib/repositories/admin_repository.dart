import '../core/api_client.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/user_device.dart';
import '../models/merchant.dart';
import '../models/merchant_device.dart';
import '../models/merchant_fee_tier.dart';
import '../models/platform_fee_settings.dart';
import '../models/branch_hours.dart';
import '../models/driver.dart';
import '../models/bank.dart';
import '../models/driver_wallet_request.dart';
import '../models/admin_delivery.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/inventory_item.dart';
import '../models/shipping_fee_settings.dart';
import '../models/delivery_radius_settings.dart';
import '../models/voucher.dart';
import '../models/voucher_amount_tier.dart';
import '../models/order_settings.dart';
import '../models/auto_accept_settings.dart';
import '../models/driver_accept_settings.dart';
import '../models/driver_dispatch_settings.dart';
import '../models/pickup_proximity_settings.dart';
import '../models/bank_account_settings.dart';
import '../models/admin_contact_settings.dart';
import '../models/pwa_reminder_settings.dart';
import '../models/price_report.dart';
import '../models/issue_report.dart';
import '../models/admin_notification.dart';
import '../models/notification_inbox_item.dart';
import '../models/notification_settings.dart';
import '../models/nav_tab_icon.dart';
import '../models/icon_library.dart';
import '../models/driver_finance_settings.dart';
import '../models/otp_settings.dart';
import '../models/chat_settings.dart';
import '../models/driver_wallet_summary.dart';
import '../models/merchant_wallet_summary.dart';
import '../models/merchant_wallet_request.dart';
import '../models/merchant_classification.dart';
import '../models/topping.dart';

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

  // ---- Thiết bị đã đăng nhập của 1 người dùng (khách/tài xế/cửa hàng...) ----

  Future<List<UserDevice>> userDevices(String userId) async {
    final list = await _api.get('/admin/users/$userId/devices') as List;
    return list
        .map((e) => UserDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeUserDevice(String userId, String deviceId) async {
    await _api.delete('/admin/users/$userId/devices/$deviceId');
  }

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

  /// Xem trước dữ liệu chặn "Xoá vĩnh viễn" 1 người dùng (cửa hàng đang đứng tên, hồ sơ tài xế,
  /// đơn hàng đã đặt) — mở từ user_detail_screen.dart trước khi bấm xoá, cùng ý tưởng với
  /// orderBlockingRecords bên dưới nhưng KHÔNG có API xoá hàng loạt (đây là dữ liệu nghiệp vụ
  /// thật, không phải bảng sổ sách).
  Future<Map<String, dynamic>> userBlockingRecords(String userId) async =>
      await _api.get('/admin/users/$userId/blocking-records')
          as Map<String, dynamic>;

  /// Chuyển chủ 1 cửa hàng đang chặn xoá user sang tài khoản "HOFA Admin" dùng chung (server tự
  /// gán GAS_SYNC_OWNER_ID) — gỡ chặn mà không cần tìm chủ mới ngay.
  Future<void> transferMerchantToAdminOwner(String merchantId) async {
    await _api.post('/admin/merchants/$merchantId/transfer-to-admin-owner');
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

  /// [ownerPhone] = SĐT chủ cửa hàng — bắt buộc khi admin tự tạo hộ. Nếu [ownerPassword]
  /// có giá trị, server tạo THẲNG 1 tài khoản hoàn toàn mới với SĐT/mật khẩu này (báo lỗi
  /// nếu SĐT đã có tài khoản); để trống thì gắn cửa hàng vào 1 tài khoản đã có sẵn như cũ.
  Future<Merchant> createMerchant(
    Map<String, dynamic> data, {
    required String ownerPhone,
    String? ownerPassword,
    String? ownerFullName,
  }) async => Merchant.fromJson(
    await _api.post(
          '/merchants',
          body: {
            ...data,
            'owner_phone': ownerPhone,
            if (ownerPassword != null && ownerPassword.isNotEmpty)
              'owner_password': ownerPassword,
            if (ownerFullName != null && ownerFullName.isNotEmpty)
              'owner_full_name': ownerFullName,
          },
        )
        as Map<String, dynamic>,
  );

  /// [ownerPhone]/[ownerPassword]/[ownerFullName]: dùng khi chuyển cửa hàng mua hộ (chưa có chủ
  /// thật) sang cửa hàng thường — cùng quy tắc với [createMerchant]: có [ownerPassword] thì tạo
  /// THẲNG 1 tài khoản hoàn toàn mới; để trống thì gắn vào 1 tài khoản đã có sẵn theo SĐT.
  Future<Merchant> updateMerchant(
    String id,
    Map<String, dynamic> data, {
    String? ownerPhone,
    String? ownerPassword,
    String? ownerFullName,
  }) async => Merchant.fromJson(
    await _api.patch(
          '/merchants/$id',
          body: {
            ...data,
            if (ownerPhone != null && ownerPhone.isNotEmpty)
              'owner_phone': ownerPhone,
            if (ownerPassword != null && ownerPassword.isNotEmpty)
              'owner_password': ownerPassword,
            if (ownerFullName != null && ownerFullName.isNotEmpty)
              'owner_full_name': ownerFullName,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteMerchant(String id) async {
    await _api.delete('/merchants/$id');
  }

  /// Ghi đè toàn bộ phân loại của 1 cửa hàng (xoá hết rồi gắn lại đúng danh sách [classificationIds]).
  Future<void> setMerchantClassifications(
    String merchantId,
    List<String> classificationIds,
  ) async {
    await _api.put(
      '/merchants/$merchantId/classifications',
      body: {'classification_ids': classificationIds},
    );
  }

  // ---- Phân loại cửa hàng (Nhà hàng/Cà phê/Siêu thị mini...) ----

  Future<List<MerchantClassification>> merchantClassifications() async {
    final list = await _api.get('/merchant-classifications') as List;
    return list
        .map((e) => MerchantClassification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MerchantClassification> createMerchantClassification({
    required String name,
    int? sortOrder,
  }) async => MerchantClassification.fromJson(
    await _api.post(
          '/merchant-classifications',
          body: {'name': name, if (sortOrder != null) 'sort_order': sortOrder},
        )
        as Map<String, dynamic>,
  );

  Future<MerchantClassification> updateMerchantClassification(
    String id,
    Map<String, dynamic> data,
  ) async => MerchantClassification.fromJson(
    await _api.patch('/merchant-classifications/$id', body: data)
        as Map<String, dynamic>,
  );

  Future<void> deleteMerchantClassification(String id) async {
    await _api.delete('/merchant-classifications/$id');
  }

  // ---- Thiết bị đăng nhập của cửa hàng (chủ + nhân viên) ----

  Future<List<MerchantDevice>> merchantDevices(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/devices') as List;
    return list
        .map((e) => MerchantDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Tắt" — xoá push_token, ngừng gửi thông báo tới máy đó nhưng vẫn giữ lịch sử đăng nhập.
  Future<void> disableMerchantDevice(String merchantId, String deviceId) async {
    await _api.patch('/merchants/$merchantId/devices/$deviceId');
  }

  Future<void> deleteMerchantDevice(String merchantId, String deviceId) async {
    await _api.delete('/merchants/$merchantId/devices/$deviceId');
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

  /// Công tắc "Tạm nghỉ" — [isOpen]=false đóng tay VÔ THỜI HẠN (break_until=null), true mở
  /// lại (luôn xoá break_until dù đang đóng tay hay từng hẹn giờ). Xem
  /// PATCH /branches/:id/toggle-open, hofa-db/78_branch_operating_hours_gate.sql.
  Future<Branch> toggleBranchOpen(
    String branchId, {
    required bool isOpen,
    DateTime? breakUntil,
  }) async => Branch.fromJson(
    await _api.patch(
          '/branches/$branchId/toggle-open',
          body: {
            'is_open': isOpen,
            if (breakUntil != null)
              'break_until': breakUntil.toUtc().toIso8601String(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<List<BranchHour>> branchHours(String branchId) async {
    final list = await _api.get('/branches/$branchId/hours') as List;
    return list
        .map((e) => BranchHour.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BranchHour>> setBranchHours(
    String branchId,
    List<BranchHour> hours,
  ) async {
    final list =
        await _api.put(
              '/branches/$branchId/hours',
              body: {'hours': hours.map((h) => h.toJson()).toList()},
            )
            as List;
    return list
        .map((e) => BranchHour.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Bậc phí mua hộ (merchant_type = 'buy_on_behalf') ----

  Future<List<MerchantFeeTier>> merchantFeeTiers(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/fee-tiers') as List;
    return list
        .map((e) => MerchantFeeTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MerchantFeeTier> createFeeTier(
    String merchantId,
    Map<String, dynamic> data,
  ) async => MerchantFeeTier.fromJson(
    await _api.post('/merchants/$merchantId/fee-tiers', body: data)
        as Map<String, dynamic>,
  );

  Future<MerchantFeeTier> updateFeeTier(
    String id,
    Map<String, dynamic> data,
  ) async => MerchantFeeTier.fromJson(
    await _api.patch('/fee-tiers/$id', body: data) as Map<String, dynamic>,
  );

  Future<void> deleteFeeTier(String id) async {
    await _api.delete('/fee-tiers/$id');
  }

  /// Xoá hết bậc phí riêng đang có của cửa hàng rồi copy lại đúng bậc phí mặc định toàn sàn
  /// (buy_on_behalf_fee_basis + merchant_fee_tiers) — nút "Đưa về mặc định toàn sàn" ở
  /// MerchantFeeTiersCard. Trả về danh sách bậc phí MỚI sau khi reset.
  Future<List<MerchantFeeTier>> resetMerchantFeeTiersToPlatformDefault(
    String merchantId,
  ) async {
    final list =
        await _api.post(
              '/merchants/$merchantId/fee-tiers/reset-to-platform-default',
            )
            as List;
    return list
        .map((e) => MerchantFeeTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Phí mua hộ mặc định toàn sàn (copy sang merchant_fee_tiers cho cửa hàng
  // buy_on_behalf mới tạo — xem hofa-db/87_platform_buy_on_behalf_fee_defaults.sql) ----

  Future<PlatformFeeData> platformFeeSettings() async =>
      PlatformFeeData.fromJson(
        await _api.get('/platform-fee-settings') as Map<String, dynamic>,
      );

  Future<PlatformFeeSettings> updatePlatformFeeBasis(String feeBasis) async =>
      PlatformFeeSettings.fromJson(
        await _api.patch(
              '/platform-fee-settings',
              body: {'fee_basis': feeBasis},
            )
            as Map<String, dynamic>,
      );

  Future<PlatformFeeTier> createPlatformFeeTier(
    Map<String, dynamic> data,
  ) async => PlatformFeeTier.fromJson(
    await _api.post('/platform-fee-tiers', body: data) as Map<String, dynamic>,
  );

  Future<PlatformFeeTier> updatePlatformFeeTier(
    String id,
    Map<String, dynamic> data,
  ) async => PlatformFeeTier.fromJson(
    await _api.patch('/platform-fee-tiers/$id', body: data)
        as Map<String, dynamic>,
  );

  Future<void> deletePlatformFeeTier(String id) async {
    await _api.delete('/platform-fee-tiers/$id');
  }

  // ---- Nhóm topping (thư viện dùng chung của 1 cửa hàng) — cùng endpoint với
  // hofa_store_app/lib/repositories/product_repository.dart, admin qua được nhờ
  // requireMerchantAccess() cho role admin luôn qua (xem server/src/utils.js). ----

  Future<List<ToppingGroup>> merchantToppingGroups(String merchantId) async {
    final list =
        await _api.get('/merchants/$merchantId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ToppingGroup> createToppingGroup(
    String merchantId,
    Map<String, dynamic> data,
  ) async => ToppingGroup.fromJson(
    await _api.post('/merchants/$merchantId/topping-groups', body: data)
        as Map<String, dynamic>,
  );

  Future<void> updateToppingGroup(String id, Map<String, dynamic> data) async {
    await _api.patch('/topping-groups/$id', body: data);
  }

  Future<void> deleteToppingGroup(String id) async {
    await _api.delete('/topping-groups/$id');
  }

  Future<Topping> createTopping(
    String groupId,
    Map<String, dynamic> data,
  ) async => Topping.fromJson(
    await _api.post('/topping-groups/$groupId/toppings', body: data)
        as Map<String, dynamic>,
  );

  Future<void> updateTopping(String id, Map<String, dynamic> data) async {
    await _api.patch('/toppings/$id', body: data);
  }

  Future<void> deleteTopping(String id) async {
    await _api.delete('/toppings/$id');
  }

  // ---- Sản phẩm/menu 1 cửa hàng — cùng endpoint với
  // hofa_store_app/lib/repositories/product_repository.dart (đã nhận merchantId/productId/
  // variantId tường minh sẵn từ trước), admin qua được nhờ requireMerchantAccess() cho role
  // admin luôn qua (xem server/src/utils.js). Dùng ở merchant_products_screen.dart +
  // merchant_product_form_screen.dart. ----

  Future<List<MerchantCategory>> merchantCategories({
    required String merchantId,
    String? categoryId,
  }) async {
    final list =
        await _api.get(
              '/merchant-categories',
              query: {
                'merchant_id': merchantId,
                if (categoryId != null) 'category_id': categoryId,
              },
            )
            as List;
    return list
        .map((e) => MerchantCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MerchantCategory> createMerchantCategory({
    required String merchantId,
    required String categoryId,
    required String name,
  }) async => MerchantCategory.fromJson(
    await _api.post(
          '/merchant-categories',
          body: {
            'merchant_id': merchantId,
            'category_id': categoryId,
            'name': name,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateMerchantCategory(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _api.patch('/merchant-categories/$id', body: data);
  }

  Future<void> deleteMerchantCategory(String id) async {
    await _api.delete('/merchant-categories/$id');
  }

  Future<List<Product>> merchantProducts(String merchantId) async {
    final list =
        await _api.get(
              '/products',
              query: {'merchant_id': merchantId, 'limit': 100},
            )
            as List;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Product> product(String id) async =>
      Product.fromJson(await _api.get('/products/$id') as Map<String, dynamic>);

  Future<Product> createProduct(Map<String, dynamic> data) async =>
      Product.fromJson(
        await _api.post('/products', body: data) as Map<String, dynamic>,
      );

  Future<void> updateProduct(String id, Map<String, dynamic> data) async {
    await _api.patch('/products/$id', body: data);
  }

  Future<void> deleteProduct(String id) async {
    await _api.delete('/products/$id');
  }

  Future<ProductVariant> createVariant(
    String productId,
    Map<String, dynamic> data,
  ) async => ProductVariant.fromJson(
    await _api.post('/products/$productId/variants', body: data)
        as Map<String, dynamic>,
  );

  Future<void> updateVariant(String id, Map<String, dynamic> data) async {
    await _api.patch('/variants/$id', body: data);
  }

  Future<void> deleteVariant(String id) async {
    await _api.delete('/variants/$id');
  }

  Future<List<WholesaleTier>> wholesaleTiers(String variantId) async {
    final list = await _api.get('/variants/$variantId/wholesale-tiers') as List;
    return list
        .map((e) => WholesaleTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WholesaleTier> createWholesaleTier(
    String variantId,
    Map<String, dynamic> data,
  ) async => WholesaleTier.fromJson(
    await _api.post('/variants/$variantId/wholesale-tiers', body: data)
        as Map<String, dynamic>,
  );

  Future<void> updateWholesaleTier(String id, Map<String, dynamic> data) async {
    await _api.patch('/wholesale-tiers/$id', body: data);
  }

  Future<void> deleteWholesaleTier(String id) async {
    await _api.delete('/wholesale-tiers/$id');
  }

  /// Nhóm topping đang gắn vào 1 sản phẩm.
  Future<List<ToppingGroup>> productToppingGroups(String productId) async {
    final list = await _api.get('/products/$productId/topping-groups') as List;
    return list
        .map((e) => ToppingGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Đặt lại toàn bộ danh sách nhóm topping gắn vào 1 sản phẩm (thay thế, không cộng dồn).
  Future<void> setProductToppingGroups(
    String productId,
    List<String> groupIds,
  ) async {
    await _api.put(
      '/products/$productId/topping-groups',
      body: {'group_ids': groupIds},
    );
  }

  // ---- Tồn kho (dùng trong merchant_product_form_screen.dart) ----

  Future<List<InventoryItem>> inventory(String branchId) async {
    final list = await _api.get('/branches/$branchId/inventory') as List;
    return list
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> adjustInventory({
    required String branchId,
    required String variantId,
    required String moveType,
    required int quantity,
    String? note,
  }) async {
    final data =
        await _api.post(
              '/inventory/adjust',
              body: {
                'branch_id': branchId,
                'variant_id': variantId,
                'move_type': moveType,
                'quantity': quantity,
                if (note != null && note.isNotEmpty) 'note': note,
              },
            )
            as Map<String, dynamic>;
    return (data['balance_after'] as num).toInt();
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

  Future<Driver> rejectDriver(String id, String reason) async =>
      Driver.fromJson(
        await _api.post('/admin/drivers/$id/reject', body: {'reason': reason})
            as Map<String, dynamic>,
      );

  /// Admin sửa trực tiếp hồ sơ tài xế (CCCD, GPLX, xe, ngân hàng) — không đổi trạng thái duyệt.
  Future<Driver> updateDriver(String id, Map<String, dynamic> data) async =>
      Driver.fromJson(
        await _api.patch('/admin/drivers/$id', body: data)
            as Map<String, dynamic>,
      );

  /// Gỡ tài xế bị kẹt trạng thái (thường là 'busy' không tự về 'online' được) — không đụng gì
  /// tới deliveries, chỉ đổi đúng cột status của drivers.
  Future<Driver> forceDriverStatus(String id, String status) async =>
      Driver.fromJson(
        await _api.patch('/admin/drivers/$id/status', body: {'status': status})
            as Map<String, dynamic>,
      );

  /// Chi tiết đầy đủ 1 tài xế (kèm thông tin người dùng) cho driver_detail_screen.dart.
  Future<Driver> driverDetail(String id) async => Driver.fromJson(
    await _api.get('/admin/drivers/$id') as Map<String, dynamic>,
  );

  Future<void> deleteDriver(String id) async {
    await _api.delete('/admin/drivers/$id');
  }

  /// Xem trước dữ liệu chặn "Xoá tài xế" (chuyến giao chưa xong, số dư ví) — xem
  /// driver_blocking_records_screen.dart.
  Future<Map<String, dynamic>> driverBlockingRecords(String id) async =>
      await _api.get('/admin/drivers/$id/blocking-records')
          as Map<String, dynamic>;

  // ---- Đơn hàng ----

  Future<List<Order>> orders({
    String? status,
    String? q,
    // Ngoại lệ chỉ admin có — để trống thì xem mọi đơn không giới hạn thời gian (khác app
    // khách/cửa hàng phải chọn 1 trong 4 khoảng nhanh), có giá trị thì lọc theo created_at.
    String? from,
    String? to,
    // true = chỉ đơn mua hộ đang chờ tài xế lấy nhưng chưa ai nhận — dùng cho chip lọc nhanh
    // "Mua hộ cần tài xế" ở orders_screen.dart.
    bool needsDriver = false,
    int limit = 100,
  }) async {
    final list =
        await _api.get(
              '/admin/orders',
              query: {
                'limit': limit,
                if (status != null) 'status': status,
                if (q != null && q.isNotEmpty) 'q': q,
                if (from != null) 'from': from,
                if (to != null) 'to': to,
                if (needsDriver) 'needs_driver': 'true',
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
  /// buộc khoá ngoại (vd đã có giao dịch thanh toán) thì server trả lỗi cụ thể từ Postgres —
  /// dùng orderBlockingRecords/deleteOrderBlockingRecords bên dưới để dọn trước khi xoá lại.
  Future<void> deleteOrder(String id) async {
    await _api.delete('/admin/orders/$id');
  }

  /// 4 bảng có thể chặn xoá 1 đơn (driver_wallet_transactions/payments/
  /// merchant_wallet_transactions/driver_cod_settlement_items) — xem
  /// server/src/routes/order-blocking-records.js. Trả nguyên các dòng để admin xem trước khi
  /// xoá, không chỉ đếm số lượng.
  Future<Map<String, dynamic>> orderBlockingRecords(String orderId) async =>
      await _api.get('/admin/orders/$orderId/blocking-records')
          as Map<String, dynamic>;

  /// [tables] null = xoá cả 4 bảng; truyền vào để xoá riêng từng bảng. Trả về số dòng đã xoá
  /// theo từng bảng.
  Future<Map<String, dynamic>> deleteOrderBlockingRecords(
    String orderId, {
    List<String>? tables,
  }) async {
    final data =
        await _api.delete(
              '/admin/orders/$orderId/blocking-records',
              query: tables != null ? {'tables': tables.join(',')} : null,
            )
            as Map<String, dynamic>;
    return data['deleted'] as Map<String, dynamic>;
  }

  // ---- Giám sát chuyến giao hàng ----

  /// status=null lấy các chuyến đang hoạt động (mặc định phía server), 'all' bỏ lọc, hoặc 1
  /// giá trị delivery_status cụ thể.
  Future<List<AdminDelivery>> deliveries({String? status}) async {
    final list =
        await _api.get(
              '/admin/deliveries',
              query: {'limit': 200, if (status != null) 'status': status},
            )
            as List;
    return list
        .map((e) => AdminDelivery.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Chi tiết 1 chuyến — kèm đầy đủ điểm lấy hàng (branch*) + điểm giao hàng (ship*) mà bản
  /// danh sách (deliveries()) không có, dùng cho màn chi tiết chuyến giao.
  Future<AdminDelivery> delivery(String id) async => AdminDelivery.fromJson(
    await _api.get('/admin/deliveries/$id') as Map<String, dynamic>,
  );

  /// Đổi tay trạng thái 1 chuyến — không đi qua RPC nghiệp vụ (không đụng tồn kho/ví tài xế),
  /// xem comment PATCH /admin/deliveries/:id/status phía server.
  Future<void> forceDeliveryStatus(String id, String status) async {
    await _api.patch('/admin/deliveries/$id/status', body: {'status': status});
  }

  /// Sửa điểm GIAO hàng của đơn (ship_*) — điểm LẤY hàng sửa qua updateBranch() ở trên vì đó là
  /// dữ liệu của chi nhánh, không phải của riêng đơn/chuyến này.
  Future<void> updateOrderShipping(
    String orderId,
    Map<String, dynamic> data,
  ) async {
    await _api.patch('/admin/orders/$orderId/shipping', body: data);
  }

  Future<void> deleteDelivery(String id) async {
    await _api.delete('/admin/deliveries/$id');
  }

  /// Xoá hàng loạt — truyền đúng 1 trong 3: [ids], [statusIn] (khớp đúng bộ lọc đang xem, dùng
  /// cho nút "Xoá tất cả"), hoặc [all] (xoá toàn bộ bảng, không lọc gì).
  Future<int> deleteDeliveries({
    List<String>? ids,
    List<String>? statusIn,
    bool all = false,
  }) async {
    final data =
        await _api.post(
              '/admin/deliveries/delete',
              body: {
                if (ids != null && ids.isNotEmpty) 'ids': ids,
                if (statusIn != null && statusIn.isNotEmpty)
                  'status_in': statusIn,
                if (all) 'all': true,
              },
            )
            as Map<String, dynamic>;
    return (data['deleted'] as num?)?.toInt() ?? 0;
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

  // Cố ý không có deleteCategory — xem comment DELETE /categories/:id (đã gỡ khỏi server)
  // trong server/src/routes/products.js.

  // ---- Danh sách ngân hàng (tài xế chọn lúc đăng ký/sửa hồ sơ) ----

  Future<List<Bank>> banks() async {
    final list = await _api.get('/banks') as List;
    return list.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Bank> createBank({
    required String name,
    required String bin,
    int? sortOrder,
  }) async => Bank.fromJson(
    await _api.post(
          '/banks',
          body: {
            'name': name,
            'bin': bin,
            if (sortOrder != null) 'sort_order': sortOrder,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Bank> updateBank(String id, Map<String, dynamic> data) async =>
      Bank.fromJson(
        await _api.patch('/banks/$id', body: data) as Map<String, dynamic>,
      );

  Future<void> deleteBank(String id) async {
    await _api.delete('/banks/$id');
  }

  // ---- Icon tabbar tuỳ chỉnh (4 app) ----

  Future<List<NavTabIcon>> navIcons() async {
    final list = await _api.get('/nav-icons') as List;
    return list
        .map((e) => NavTabIcon.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [iconUrl] = null thì xoá icon tuỳ chỉnh, tab quay lại dùng icon Material mặc định.
  Future<void> setNavIcon(String app, String tabKey, String? iconUrl) async {
    await _api.put('/nav-icons/$app/$tabKey', body: {'icon_url': iconUrl});
  }

  // ---- Thư viện icon online (Iconify) đã bật ----

  Future<List<IconLibrary>> iconLibraries() async {
    final list = await _api.get('/icon-libraries') as List;
    return list
        .map((e) => IconLibrary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> enableIconLibrary(String prefix, String name) async {
    await _api.post('/icon-libraries', body: {'prefix': prefix, 'name': name});
  }

  Future<void> disableIconLibrary(String prefix) async {
    await _api.delete('/icon-libraries/$prefix');
  }

  // ---- Ví tài xế: duyệt nạp/rút tiền ----

  Future<List<DriverWalletRequest>> walletDeposits({String? status}) async {
    final list =
        await _api.get(
              '/admin/wallet-deposits',
              query: {'limit': 100, if (status != null) 'status': status},
            )
            as List;
    return list
        .map((e) => DriverWalletRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmWalletDeposit(String id) async {
    await _api.post('/admin/wallet-deposits/$id/confirm');
  }

  Future<List<DriverWalletRequest>> walletWithdrawals({String? status}) async {
    final list =
        await _api.get(
              '/admin/wallet-withdrawals',
              query: {'limit': 100, if (status != null) 'status': status},
            )
            as List;
    return list
        .map((e) => DriverWalletRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmWalletWithdrawal(String id) async {
    await _api.post('/admin/wallet-withdrawals/$id/confirm');
  }

  Future<void> rejectWalletWithdrawal(String id, {String? reason}) async {
    await _api.post(
      '/admin/wallet-withdrawals/$id/reject',
      body: {if (reason != null) 'reason': reason},
    );
  }

  // ---- Ví tài xế: tổng quan + điều chỉnh tay ----

  Future<DriverWalletSummary> driverWalletSummary() async =>
      DriverWalletSummary.fromJson(
        await _api.get('/admin/driver-wallets/summary') as Map<String, dynamic>,
      );

  /// wallet: 'cod' | 'earning' — amount có dấu (+/-), reason bắt buộc (server yêu cầu, xem
  /// CHECK driver_wallet_tx_adjustment_needs_note).
  Future<void> adjustDriverWallet(
    String driverId, {
    required String wallet,
    required int amount,
    required String reason,
  }) async {
    await _api.post(
      '/admin/drivers/$driverId/wallet-adjustment',
      body: {'wallet': wallet, 'amount': amount, 'reason': reason},
    );
  }

  // ---- Cấu hình tài chính tài xế ----

  Future<DriverFinanceSettings> driverFinanceSettings() async {
    final data = await _api.get('/driver-finance-settings');
    return data == null
        ? DriverFinanceSettings.fallback()
        : DriverFinanceSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<DriverFinanceSettings> updateDriverFinanceSettings(
    DriverFinanceSettings settings,
  ) async => DriverFinanceSettings.fromJson(
    await _api.patch('/driver-finance-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Ngưỡng OTP xác nhận giao/nhận ----

  Future<OtpSettings> otpSettings() async {
    final data = await _api.get('/otp-settings');
    return data == null
        ? OtpSettings.fallback()
        : OtpSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<OtpSettings> updateOtpSettings(OtpSettings settings) async =>
      OtpSettings.fromJson(
        await _api.patch('/otp-settings', body: settings.toJson())
            as Map<String, dynamic>,
      );

  // ---- Nhắn tin trong đơn hàng ----

  Future<ChatSettings> chatSettings() async {
    final data = await _api.get('/chat-settings');
    return data == null
        ? ChatSettings.fallback()
        : ChatSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<ChatSettings> updateChatSettings(ChatSettings settings) async =>
      ChatSettings.fromJson(
        await _api.patch('/chat-settings', body: settings.toJson())
            as Map<String, dynamic>,
      );

  // ---- Ví cửa hàng: tổng quan + rút tiền + điều chỉnh tay ----

  Future<MerchantWalletSummary> merchantWalletSummary() async =>
      MerchantWalletSummary.fromJson(
        await _api.get('/admin/merchant-wallets/summary')
            as Map<String, dynamic>,
      );

  Future<List<MerchantWalletBalance>> merchantWallets() async {
    final list =
        await _api.get('/admin/merchant-wallets', query: {'limit': 200})
            as List;
    return list
        .map((e) => MerchantWalletBalance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MerchantWalletRequest>> merchantWalletWithdrawals({
    String? status,
  }) async {
    final list =
        await _api.get(
              '/admin/merchant-wallet-withdrawals',
              query: {'limit': 100, if (status != null) 'status': status},
            )
            as List;
    return list
        .map((e) => MerchantWalletRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmMerchantWalletWithdrawal(String id) async {
    await _api.post('/admin/merchant-wallet-withdrawals/$id/confirm');
  }

  Future<void> rejectMerchantWalletWithdrawal(
    String id, {
    String? reason,
  }) async {
    await _api.post(
      '/admin/merchant-wallet-withdrawals/$id/reject',
      body: {if (reason != null) 'reason': reason},
    );
  }

  Future<void> adjustMerchantWallet(
    String merchantId, {
    required int amount,
    required String reason,
  }) async {
    await _api.post(
      '/admin/merchants/$merchantId/wallet-adjustment',
      body: {'amount': amount, 'reason': reason},
    );
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

  // ---- Bán kính giao hàng mặc định ----

  Future<DeliveryRadiusSettings> deliveryRadiusSettings() async {
    final data = await _api.get('/delivery-radius-settings');
    return data == null
        ? DeliveryRadiusSettings.fallback()
        : DeliveryRadiusSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<DeliveryRadiusSettings> updateDeliveryRadiusSettings(
    DeliveryRadiusSettings settings,
  ) async => DeliveryRadiusSettings.fromJson(
    await _api.patch('/delivery-radius-settings', body: settings.toJson())
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

  // ---- Thông số "Tự động nhận đơn" ----

  Future<AutoAcceptSettings> autoAcceptSettings() async {
    final data = await _api.get('/auto-accept-settings');
    return data == null
        ? AutoAcceptSettings.fallback()
        : AutoAcceptSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<AutoAcceptSettings> updateAutoAcceptSettings(
    AutoAcceptSettings settings,
  ) async => AutoAcceptSettings.fromJson(
    await _api.patch('/auto-accept-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Thông số "Nhận đơn" tài xế ----

  Future<DriverAcceptSettings> driverAcceptSettings() async {
    final data = await _api.get('/driver-accept-settings');
    return data == null
        ? DriverAcceptSettings.fallback()
        : DriverAcceptSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<DriverAcceptSettings> updateDriverAcceptSettings(
    DriverAcceptSettings settings,
  ) async => DriverAcceptSettings.fromJson(
    await _api.patch('/driver-accept-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Thông số quét tìm tài xế khi chưa có ai nhận ----

  Future<DriverDispatchSettings> driverDispatchSettings() async {
    final data = await _api.get('/driver-dispatch-settings');
    return data == null
        ? DriverDispatchSettings.fallback()
        : DriverDispatchSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<DriverDispatchSettings> updateDriverDispatchSettings(
    DriverDispatchSettings settings,
  ) async => DriverDispatchSettings.fromJson(
    await _api.patch('/driver-dispatch-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Bán kính bắt buộc lúc tài xế xác nhận "Đã lấy hàng" (đơn mua hộ) ----

  Future<PickupProximitySettings> pickupProximitySettings() async {
    final data = await _api.get('/pickup-proximity-settings');
    return data == null
        ? PickupProximitySettings.fallback()
        : PickupProximitySettings.fromJson(data as Map<String, dynamic>);
  }

  Future<PickupProximitySettings> updatePickupProximitySettings(
    PickupProximitySettings settings,
  ) async => PickupProximitySettings.fromJson(
    await _api.patch('/pickup-proximity-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  /// Admin chọn "Quét tiếp" cho 1 đơn đang kẹt chờ tài xế — reset lại từ đầu chu kỳ quét.
  Future<Order> continueDriverSearch(String orderId) async => Order.fromJson(
    await _api.post('/admin/orders/$orderId/driver-search/continue')
        as Map<String, dynamic>,
  );

  /// Quét NGAY 1 lượt tìm tài xế online gần nhất cho đơn — chủ yếu dùng cho đơn mua hộ chưa
  /// có ai nhận. Trả về tên tài xế vừa được gán (null nếu response không có, không nên xảy ra
  /// vì gán thành công server luôn kèm driver_name) để hiện xác nhận cho admin.
  Future<String?> rescanOrderDriver(String orderId) async {
    final data =
        await _api.post('/admin/orders/$orderId/rescan-driver')
            as Map<String, dynamic>;
    return data['driver_name'] as String?;
  }

  /// Admin chỉ định thẳng 1 tài xế cho đơn mua hộ (thay vì để hệ thống tự quét) — cùng route
  /// khách hàng dùng để tự chọn/chọn lại tài xế, server đã cho phép role admin gọi.
  Future<bool> selectDriverForOrder(String orderId, String driverId) async {
    final data =
        await _api.post(
              '/orders/$orderId/select-driver',
              body: {'driver_id': driverId},
            )
            as Map<String, dynamic>;
    return data['assigned'] == true;
  }

  // ---- Thông tin tài khoản ngân hàng (VietQR) ----

  Future<BankAccountSettings> bankAccountSettings() async {
    final data = await _api.get('/bank-account-settings');
    return data == null
        ? BankAccountSettings.fallback()
        : BankAccountSettings.fromJson(data as Map<String, dynamic>);
  }

  // ---- SĐT liên hệ admin/hỗ trợ ----

  Future<AdminContactSettings> adminContactSettings() async {
    final data = await _api.get('/admin-contact-settings');
    return data == null
        ? AdminContactSettings.fallback()
        : AdminContactSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<AdminContactSettings> updateAdminContactSettings(
    AdminContactSettings settings,
  ) async => AdminContactSettings.fromJson(
    await _api.patch('/admin-contact-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Chu kỳ nhắc cài PWA (app Khách) ----

  Future<PwaReminderSettings> pwaReminderSettings() async {
    final data = await _api.get('/pwa-reminder-settings');
    return data == null
        ? PwaReminderSettings.fallback()
        : PwaReminderSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<PwaReminderSettings> updatePwaReminderSettings(
    PwaReminderSettings settings,
  ) async => PwaReminderSettings.fromJson(
    await _api.patch('/pwa-reminder-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  // ---- Báo cáo giá sai ----

  Future<List<PriceReport>> priceReports({String? status}) async {
    final list =
        await _api.get(
              '/admin/price-reports',
              query: {if (status != null) 'status': status},
            )
            as List;
    return list
        .map((e) => PriceReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approvePriceReport(String id, {required int finalPrice}) async {
    await _api.patch(
      '/admin/price-reports/$id',
      body: {'status': 'approved', 'final_price': finalPrice},
    );
  }

  Future<void> rejectPriceReport(String id) async {
    await _api.patch('/admin/price-reports/$id', body: {'status': 'rejected'});
  }

  // ---- Báo cáo sự cố tài xế/cửa hàng ----

  Future<List<IssueReport>> issueReports({
    String? status,
    String? reporterType,
  }) async {
    final list =
        await _api.get(
              '/admin/issue-reports',
              query: {
                'limit': 100,
                if (status != null) 'status': status,
                if (reporterType != null) 'reporter_type': reporterType,
              },
            )
            as List;
    return list
        .map((e) => IssueReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolveIssueReport(String id, {String? adminNote}) async {
    await _api.patch(
      '/admin/issue-reports/$id',
      body: {if (adminNote != null) 'admin_note': adminNote},
    );
  }

  Future<BankAccountSettings> updateBankAccountSettings(
    BankAccountSettings settings,
  ) async => BankAccountSettings.fromJson(
    await _api.patch('/bank-account-settings', body: settings.toJson())
        as Map<String, dynamic>,
  );

  /// Xác nhận đã nhận chuyển khoản cho 1 đơn pending_payment — gọi ĐÚNG POST /payments (không
  /// phải PATCH /orders/:id/status) vì đây là hàm duy nhất vừa ghi lại giao dịch (bảng payments)
  /// vừa tự chuyển đơn sang 'placed' (record_payment RPC) và kích hoạt dispatch tự động cho đơn
  /// mua hộ (orderOffer.dispatchBuyOnBehalfOrder, gọi từ routes/payments.js).
  Future<void> confirmPayment(String orderId, int amount) async {
    await _api.post(
      '/payments',
      body: {'order_id': orderId, 'method': 'bank_transfer', 'amount': amount},
    );
  }

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

  /// Xoá 1 đợt gửi khỏi "Lịch sử đã gửi" — server CASCADE xoá luôn thông báo này khỏi hộp thư
  /// của MỌI người đã nhận (source_notification_id, xem hofa-db/93_notifications_source_link.sql).
  Future<void> deleteNotification(String id) async {
    await _api.delete('/admin/notifications/$id');
  }

  /// Xoá TOÀN BỘ lịch sử đã gửi (kèm hộp thư người nhận tương ứng) — dùng cẩn thận.
  Future<void> deleteAllNotifications() async {
    await _api.delete('/admin/notifications', query: {'confirm': 'all'});
  }

  Future<AdminNotification> sendNotification({
    required String title,
    required String body,
    required String audienceType,
    List<String>? userIds,
    List<String>? merchantIds,
    bool showBadge = false,
    String? targetScreen,
    String category = 'system',
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
            if (targetScreen != null) 'target_screen': targetScreen,
            'category': category,
          },
        )
        as Map<String, dynamic>,
  );

  /// Hộp thư THẬT của từng người nhận trong 1 phạm vi đối tượng — khác notifications() ở
  /// trên (đó là log các đợt gửi). audienceType bắt buộc; bỏ trống cả merchantIds lẫn
  /// userIds nghĩa là TOÀN BỘ audienceType đó (mọi khách hàng/cửa hàng/tài xế).
  Future<List<NotificationInboxItem>> notificationInbox({
    required String audienceType,
    List<String>? merchantIds,
    List<String>? userIds,
    int limit = 200,
    int offset = 0,
  }) async {
    final list =
        await _api.get(
              '/admin/notifications/inbox',
              query: {
                'audience_type': audienceType,
                if (merchantIds != null && merchantIds.isNotEmpty)
                  'merchant_ids': merchantIds.join(','),
                if (userIds != null && userIds.isNotEmpty)
                  'user_ids': userIds.join(','),
                'limit': limit,
                'offset': offset,
              },
            )
            as List;
    return list
        .map((e) => NotificationInboxItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Xoá đúng 1 trong 3 kiểu: [ids] (1 hoặc nhiều dòng cụ thể), [audienceType] (cả hộp thư
  /// của 1 phạm vi đối tượng — toàn bộ audienceType đó nếu bỏ trống merchantIds/userIds, hoặc
  /// chỉ các cửa hàng/người dùng/tài xế cụ thể nếu có), hoặc [all] = true (toàn bộ hộp thư
  /// mọi người dùng trên sàn).
  Future<int> deleteNotificationInbox({
    List<String>? ids,
    String? audienceType,
    List<String>? merchantIds,
    List<String>? userIds,
    bool all = false,
  }) async {
    final data =
        await _api.post(
              '/admin/notifications/inbox/delete',
              body: {
                if (ids != null && ids.isNotEmpty) 'ids': ids,
                if (audienceType != null) 'audience_type': audienceType,
                if (merchantIds != null && merchantIds.isNotEmpty)
                  'merchant_ids': merchantIds,
                if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
                if (all) 'all': true,
              },
            )
            as Map<String, dynamic>;
    return (data['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<NotificationSettings> notificationSettings() async =>
      NotificationSettings.fromJson(
        await _api.get('/notification-settings') as Map<String, dynamic>?,
      );

  Future<NotificationSettings> updateNotificationTtl(int? ttlHours) async =>
      NotificationSettings.fromJson(
        await _api.patch(
              '/notification-settings',
              body: {'ttl_hours': ttlHours},
            )
            as Map<String, dynamic>?,
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

  // ---- Bậc giảm giá theo giá trị đơn của voucher ----

  Future<List<VoucherAmountTier>> voucherAmountTiers(String voucherId) async {
    final list = await _api.get('/vouchers/$voucherId/amount-tiers') as List;
    return list
        .map((e) => VoucherAmountTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VoucherAmountTier> createVoucherAmountTier(
    String voucherId,
    Map<String, dynamic> data,
  ) async => VoucherAmountTier.fromJson(
    await _api.post('/vouchers/$voucherId/amount-tiers', body: data)
        as Map<String, dynamic>,
  );

  Future<VoucherAmountTier> updateVoucherAmountTier(
    String id,
    Map<String, dynamic> data,
  ) async => VoucherAmountTier.fromJson(
    await _api.patch('/voucher-amount-tiers/$id', body: data)
        as Map<String, dynamic>,
  );

  Future<void> deleteVoucherAmountTier(String id) async {
    await _api.delete('/voucher-amount-tiers/$id');
  }
}
