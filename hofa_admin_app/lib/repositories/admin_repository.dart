import '../core/api_client.dart';
import '../models/admin_stats.dart';
import '../models/user_profile.dart';
import '../models/user_detail.dart';
import '../models/merchant.dart';
import '../models/merchant_device.dart';
import '../models/merchant_fee_tier.dart';
import '../models/branch_hours.dart';
import '../models/driver.dart';
import '../models/bank.dart';
import '../models/driver_wallet_request.dart';
import '../models/admin_delivery.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/shipping_fee_settings.dart';
import '../models/voucher.dart';
import '../models/voucher_amount_tier.dart';
import '../models/order_settings.dart';
import '../models/auto_accept_settings.dart';
import '../models/driver_accept_settings.dart';
import '../models/bank_account_settings.dart';
import '../models/admin_notification.dart';
import '../models/notification_inbox_item.dart';
import '../models/notification_settings.dart';

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

  Future<Merchant> updateMerchant(String id, Map<String, dynamic> data) async =>
      Merchant.fromJson(
        await _api.patch('/merchants/$id', body: data) as Map<String, dynamic>,
      );

  Future<void> deleteMerchant(String id) async {
    await _api.delete('/merchants/$id');
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

  Future<List<BranchHour>> branchHours(String branchId) async {
    final list = await _api.get('/branches/$branchId/hours') as List;
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

  Future<Driver> rejectDriver(String id, String reason) async => Driver.fromJson(
    await _api.post('/admin/drivers/$id/reject', body: {'reason': reason}) as Map<String, dynamic>,
  );

  /// Admin sửa trực tiếp hồ sơ tài xế (CCCD, GPLX, xe, ngân hàng) — không đổi trạng thái duyệt.
  Future<Driver> updateDriver(String id, Map<String, dynamic> data) async => Driver.fromJson(
        await _api.patch('/admin/drivers/$id', body: data) as Map<String, dynamic>,
      );

  /// Gỡ tài xế bị kẹt trạng thái (thường là 'busy' không tự về 'online' được) — không đụng gì
  /// tới deliveries, chỉ đổi đúng cột status của drivers.
  Future<Driver> forceDriverStatus(String id, String status) async => Driver.fromJson(
        await _api.patch('/admin/drivers/$id/status', body: {'status': status}) as Map<String, dynamic>,
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

  // ---- Giám sát chuyến giao hàng ----

  /// status=null lấy các chuyến đang hoạt động (mặc định phía server), 'all' bỏ lọc, hoặc 1
  /// giá trị delivery_status cụ thể.
  Future<List<AdminDelivery>> deliveries({String? status}) async {
    final list = await _api.get('/admin/deliveries', query: {
      'limit': 200,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => AdminDelivery.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Chi tiết 1 chuyến — kèm đầy đủ điểm lấy hàng (branch*) + điểm giao hàng (ship*) mà bản
  /// danh sách (deliveries()) không có, dùng cho màn chi tiết chuyến giao.
  Future<AdminDelivery> delivery(String id) async =>
      AdminDelivery.fromJson(await _api.get('/admin/deliveries/$id') as Map<String, dynamic>);

  /// Đổi tay trạng thái 1 chuyến — không đi qua RPC nghiệp vụ (không đụng tồn kho/ví tài xế),
  /// xem comment PATCH /admin/deliveries/:id/status phía server.
  Future<void> forceDeliveryStatus(String id, String status) async {
    await _api.patch('/admin/deliveries/$id/status', body: {'status': status});
  }

  /// Sửa điểm GIAO hàng của đơn (ship_*) — điểm LẤY hàng sửa qua updateBranch() ở trên vì đó là
  /// dữ liệu của chi nhánh, không phải của riêng đơn/chuyến này.
  Future<void> updateOrderShipping(String orderId, Map<String, dynamic> data) async {
    await _api.patch('/admin/orders/$orderId/shipping', body: data);
  }

  Future<void> deleteDelivery(String id) async {
    await _api.delete('/admin/deliveries/$id');
  }

  /// Xoá hàng loạt — truyền đúng 1 trong 3: [ids], [statusIn] (khớp đúng bộ lọc đang xem, dùng
  /// cho nút "Xoá tất cả"), hoặc [all] (xoá toàn bộ bảng, không lọc gì).
  Future<int> deleteDeliveries({List<String>? ids, List<String>? statusIn, bool all = false}) async {
    final data = await _api.post('/admin/deliveries/delete', body: {
      if (ids != null && ids.isNotEmpty) 'ids': ids,
      if (statusIn != null && statusIn.isNotEmpty) 'status_in': statusIn,
      if (all) 'all': true,
    }) as Map<String, dynamic>;
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

  Future<void> deleteCategory(String id) async {
    await _api.delete('/categories/$id');
  }

  // ---- Danh sách ngân hàng (tài xế chọn lúc đăng ký/sửa hồ sơ) ----

  Future<List<Bank>> banks() async {
    final list = await _api.get('/banks') as List;
    return list.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Bank> createBank({required String name, required String bin, int? sortOrder}) async => Bank.fromJson(
        await _api.post('/banks', body: {
          'name': name,
          'bin': bin,
          if (sortOrder != null) 'sort_order': sortOrder,
        }) as Map<String, dynamic>,
      );

  Future<Bank> updateBank(String id, Map<String, dynamic> data) async =>
      Bank.fromJson(await _api.patch('/banks/$id', body: data) as Map<String, dynamic>);

  Future<void> deleteBank(String id) async {
    await _api.delete('/banks/$id');
  }

  // ---- Ví tài xế: duyệt nạp/rút tiền ----

  Future<List<DriverWalletRequest>> walletDeposits({String? status}) async {
    final list = await _api.get('/admin/wallet-deposits', query: {
      'limit': 100,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => DriverWalletRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> confirmWalletDeposit(String id) async {
    await _api.post('/admin/wallet-deposits/$id/confirm');
  }

  Future<List<DriverWalletRequest>> walletWithdrawals({String? status}) async {
    final list = await _api.get('/admin/wallet-withdrawals', query: {
      'limit': 100,
      if (status != null) 'status': status,
    }) as List;
    return list.map((e) => DriverWalletRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> confirmWalletWithdrawal(String id) async {
    await _api.post('/admin/wallet-withdrawals/$id/confirm');
  }

  Future<void> rejectWalletWithdrawal(String id, {String? reason}) async {
    await _api.post('/admin/wallet-withdrawals/$id/reject', body: {if (reason != null) 'reason': reason});
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

  // ---- Thông số "Tự động nhận đơn" ----

  Future<AutoAcceptSettings> autoAcceptSettings() async {
    final data = await _api.get('/auto-accept-settings');
    return data == null
        ? AutoAcceptSettings.fallback()
        : AutoAcceptSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<AutoAcceptSettings> updateAutoAcceptSettings(AutoAcceptSettings settings) async =>
      AutoAcceptSettings.fromJson(
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

  Future<DriverAcceptSettings> updateDriverAcceptSettings(DriverAcceptSettings settings) async =>
      DriverAcceptSettings.fromJson(
        await _api.patch('/driver-accept-settings', body: settings.toJson())
            as Map<String, dynamic>,
      );

  // ---- Thông tin tài khoản ngân hàng (VietQR) ----

  Future<BankAccountSettings> bankAccountSettings() async {
    final data = await _api.get('/bank-account-settings');
    return data == null
        ? BankAccountSettings.fallback()
        : BankAccountSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<BankAccountSettings> updateBankAccountSettings(BankAccountSettings settings) async =>
      BankAccountSettings.fromJson(
        await _api.patch('/bank-account-settings', body: settings.toJson())
            as Map<String, dynamic>,
      );

  /// Xác nhận đã nhận chuyển khoản cho 1 đơn pending_payment — gọi ĐÚNG POST /payments (không
  /// phải PATCH /orders/:id/status) vì đây là hàm duy nhất vừa ghi lại giao dịch (bảng payments)
  /// vừa tự chuyển đơn sang 'placed' (record_payment RPC) và kích hoạt dispatch tự động cho đơn
  /// mua hộ (orderOffer.dispatchBuyOnBehalfOrder, gọi từ routes/payments.js).
  Future<void> confirmPayment(String orderId, int amount) async {
    await _api.post('/payments', body: {
      'order_id': orderId,
      'method': 'bank_transfer',
      'amount': amount,
    });
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
    final list = await _api.get(
      '/admin/notifications/inbox',
      query: {
        'audience_type': audienceType,
        if (merchantIds != null && merchantIds.isNotEmpty) 'merchant_ids': merchantIds.join(','),
        if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds.join(','),
        'limit': limit,
        'offset': offset,
      },
    ) as List;
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
    final data = await _api.post(
      '/admin/notifications/inbox/delete',
      body: {
        if (ids != null && ids.isNotEmpty) 'ids': ids,
        if (audienceType != null) 'audience_type': audienceType,
        if (merchantIds != null && merchantIds.isNotEmpty) 'merchant_ids': merchantIds,
        if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
        if (all) 'all': true,
      },
    ) as Map<String, dynamic>;
    return (data['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<NotificationSettings> notificationSettings() async =>
      NotificationSettings.fromJson(await _api.get('/notification-settings') as Map<String, dynamic>?);

  Future<NotificationSettings> updateNotificationTtl(int? ttlHours) async => NotificationSettings.fromJson(
        await _api.patch('/notification-settings', body: {'ttl_hours': ttlHours}) as Map<String, dynamic>?,
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
    return list.map((e) => VoucherAmountTier.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<VoucherAmountTier> createVoucherAmountTier(
    String voucherId,
    Map<String, dynamic> data,
  ) async => VoucherAmountTier.fromJson(
        await _api.post('/vouchers/$voucherId/amount-tiers', body: data) as Map<String, dynamic>,
      );

  Future<VoucherAmountTier> updateVoucherAmountTier(String id, Map<String, dynamic> data) async =>
      VoucherAmountTier.fromJson(
        await _api.patch('/voucher-amount-tiers/$id', body: data) as Map<String, dynamic>,
      );

  Future<void> deleteVoucherAmountTier(String id) async {
    await _api.delete('/voucher-amount-tiers/$id');
  }
}
