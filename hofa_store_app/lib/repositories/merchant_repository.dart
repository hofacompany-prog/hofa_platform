import '../core/api_client.dart';
import '../models/bank.dart';
import '../models/merchant.dart';
import '../models/merchant_classification.dart';
import '../models/merchant_today_stats.dart';
import '../models/otp_settings.dart';
import '../models/finance_summary.dart';
import '../models/branch.dart';
import '../models/branch_hours.dart';
import '../models/prep_tier_settings.dart';
import '../models/staff_member.dart';

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
    List<String> photoUrls = const [],
    String? bankName,
    String? bankBin,
    String? bankAccountNo,
    String? bankAccountName,
  }) async => Merchant.fromJson(
    await _api.post(
          '/merchants',
          body: {
            'name': name,
            'slug': slug,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (logoUrl != null) 'logo_url': logoUrl,
            if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
            if (bankName != null) 'bank_name': bankName,
            if (bankBin != null) 'bank_bin': bankBin,
            if (bankAccountNo != null) 'bank_account_no': bankAccountNo,
            if (bankAccountName != null) 'bank_account_name': bankAccountName,
          },
        )
        as Map<String, dynamic>,
  );

  /// Danh sách ngân hàng admin quản lý — dropdown lúc tạo/sửa hồ sơ cửa hàng.
  Future<List<Bank>> banks() async {
    final list = await _api.get('/banks') as List;
    return list.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Ngưỡng giá trị đơn để bắt buộc xác nhận OTP lấy hàng — xem
  /// hofa-db/73_otp_threshold_settings.sql.
  Future<OtpSettings> otpSettings() async {
    final json = await _api.get('/otp-settings');
    return json == null
        ? OtpSettings.fallback()
        : OtpSettings.fromJson(json as Map<String, dynamic>);
  }

  Future<Merchant> updateMerchant(String id, Map<String, dynamic> data) async =>
      Merchant.fromJson(
        await _api.patch('/merchants/$id', body: data) as Map<String, dynamic>,
      );

  /// Danh sách phân loại cửa hàng (Nhà hàng/Cà phê/Siêu thị mini...) admin quản lý.
  Future<List<MerchantClassification>> merchantClassifications() async {
    final list = await _api.get('/merchant-classifications') as List;
    return list
        .map((e) => MerchantClassification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ghi đè toàn bộ phân loại của cửa hàng hiện tại (xoá hết rồi gắn lại đúng danh sách mới).
  Future<void> setMerchantClassifications(
    String merchantId,
    List<String> classificationIds,
  ) async {
    await _api.put(
      '/merchants/$merchantId/classifications',
      body: {'classification_ids': classificationIds},
    );
  }

  Future<MerchantTodayStats> todayStats(String merchantId) async =>
      MerchantTodayStats.fromJson(
        await _api.get('/merchants/$merchantId/stats/today')
            as Map<String, dynamic>,
      );

  Future<FinanceSummary> financeSummary(
    String merchantId, {
    required String period,
  }) async => FinanceSummary.fromJson(
    await _api.get(
          '/merchants/$merchantId/finance/summary',
          query: {'period': period},
        )
        as Map<String, dynamic>,
  );

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
    double? deliveryRadiusKm,
  }) async => Branch.fromJson(
    await _api.post(
          '/merchants/$merchantId/branches',
          body: {
            'name': name,
            'line1': line1,
            'province': province,
            'latitude': latitude,
            'longitude': longitude,
            'is_main': true,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (deliveryRadiusKm != null)
              'delivery_radius_km': deliveryRadiusKm,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Branch> toggleBranchOpen(String branchId, bool isOpen) async =>
      Branch.fromJson(
        await _api.patch(
              '/branches/$branchId/toggle-open',
              body: {'is_open': isOpen},
            )
            as Map<String, dynamic>,
      );

  Future<Branch> updateBranch(
    String branchId,
    Map<String, dynamic> data,
  ) async => Branch.fromJson(
    await _api.patch('/branches/$branchId', body: data) as Map<String, dynamic>,
  );

  Future<Branch> setAutoAcceptOrders(String branchId, bool value) async =>
      Branch.fromJson(
        await _api.patch(
              '/branches/$branchId',
              body: {'auto_accept_orders': value},
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

  /// Số giây dải màu chạy trên thanh xác nhận thời gian chuẩn bị ở màn chi tiết đơn — admin cấu
  /// hình ở "Thông số" (auto_accept_settings.confirm_sweep_seconds), công khai (không cần đăng
  /// nhập). Trả về mặc định 10 nếu chưa tải được kịp, không chặn màn hình vì lỗi mạng tạm thời.
  Future<int> confirmSweepSeconds() async {
    final data =
        await _api.get('/auto-accept-settings') as Map<String, dynamic>?;
    return (data?['confirm_sweep_seconds'] as num?)?.toInt() ?? 10;
  }

  /// Số giây dải màu chạy (màu khác, xem order_detail_screen.dart) khi chi nhánh TẮT "Tự động
  /// nhận đơn" — hết giờ mà chưa trượt thì tự huỷ đơn + tự đóng chi nhánh thay vì tự xác nhận.
  /// Admin cấu hình ở "Thông số" (confirm_sweep_seconds), công khai. Mặc định 300 nếu chưa tải
  /// được kịp — dài hơn hẳn confirmSweepSeconds vì hậu quả nặng hơn (huỷ đơn, không phải xác nhận).
  Future<int> manualConfirmSweepSeconds() async {
    final data =
        await _api.get('/auto-accept-settings') as Map<String, dynamic>?;
    return (data?['manual_confirm_sweep_seconds'] as num?)?.toInt() ?? 300;
  }

  /// Bậc thời gian chuẩn bị (trần +/-) — admin cấu hình ở "Thông số", công khai.
  Future<PrepTierSettings> prepTierSettings() async {
    final data =
        await _api.get('/auto-accept-settings') as Map<String, dynamic>?;
    return data == null
        ? PrepTierSettings.fromJson(const {})
        : PrepTierSettings.fromJson(data);
  }

  // ---- Nhân viên cửa hàng ----

  Future<List<StaffMember>> staff(String merchantId) async {
    final list = await _api.get('/merchants/$merchantId/staff') as List;
    return list
        .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StaffMember> createStaff({
    required String merchantId,
    required String fullName,
    required String phone,
    required String password,
    String? position,
    List<String> permissions = const [],
  }) async => StaffMember.fromJson(
    await _api.post(
          '/merchants/$merchantId/staff',
          body: {
            'full_name': fullName,
            'phone': phone,
            'password': password,
            if (position != null && position.isNotEmpty) 'position': position,
            'permissions': permissions,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> updateStaff(
    String merchantId,
    String staffId, {
    String? position,
    List<String>? permissions,
  }) async {
    await _api.patch(
      '/merchants/$merchantId/staff/$staffId',
      body: {
        if (position != null) 'position': position,
        if (permissions != null) 'permissions': permissions,
      },
    );
  }

  Future<void> deleteStaff(String merchantId, String staffId) async {
    await _api.delete('/merchants/$merchantId/staff/$staffId');
  }

  // ---- Ví cửa hàng ----

  /// Số dư ví thật (khác netIncome theo kỳ ở financeSummary) — nguồn sự thật là sổ cái
  /// merchant_wallet_transactions, xem hofa-db/64_merchant_wallet_ledger.sql.
  Future<int> walletBalance(String merchantId) async {
    final data =
        await _api.get('/merchants/$merchantId/wallet/balance')
            as Map<String, dynamic>;
    return (data['balance'] as num?)?.toInt() ?? 0;
  }

  Future<void> createWalletWithdrawal(String merchantId, int amount) async {
    await _api.post(
      '/merchants/$merchantId/wallet/withdrawals',
      body: {'amount': amount},
    );
  }
}
