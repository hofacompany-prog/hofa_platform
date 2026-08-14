import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/bank.dart';
import '../models/bank_account_settings.dart';
import '../models/driver.dart';
import '../models/driver_finance_settings.dart';
import '../models/earnings.dart';

class DriverRepository {
  final _api = ApiClient.instance;

  /// null nếu user chưa có hồ sơ tài xế (chưa đăng ký — role vẫn là 'customer'
  /// nên GET /drivers/me trả FORBIDDEN thay vì 404, coi luôn là "chưa có hồ sơ").
  Future<Driver?> me() async {
    try {
      final json = await _api.get('/drivers/me') as Map<String, dynamic>?;
      return json == null ? null : Driver.fromJson(json);
    } on ApiException catch (e) {
      if (e.code == 'FORBIDDEN') return null;
      rethrow;
    }
  }

  Map<String, dynamic> _profileBody({
    required String nationalId,
    required String licenseNo,
    required String vehicleType,
    required String vehiclePlate,
    required String bankName,
    required String bankBin,
    required String bankAccountNumber,
    required String bankAccountHolder,
    List<String> documentUrls = const [],
  }) => {
    'national_id': nationalId,
    'license_no': licenseNo,
    'vehicle_type': vehicleType,
    'vehicle_plate': vehiclePlate,
    'bank_name': bankName,
    'bank_bin': bankBin,
    'bank_account_number': bankAccountNumber,
    'bank_account_holder': bankAccountHolder,
    if (documentUrls.isNotEmpty) 'document_urls': documentUrls,
  };

  Future<Driver> register({
    required String nationalId,
    required String licenseNo,
    required String vehicleType,
    required String vehiclePlate,
    required String bankName,
    required String bankBin,
    required String bankAccountNumber,
    required String bankAccountHolder,
    List<String> documentUrls = const [],
  }) async => Driver.fromJson(
    await _api.post(
          '/drivers/register',
          body: _profileBody(
            nationalId: nationalId,
            licenseNo: licenseNo,
            vehicleType: vehicleType,
            vehiclePlate: vehiclePlate,
            bankName: bankName,
            bankBin: bankBin,
            bankAccountNumber: bankAccountNumber,
            bankAccountHolder: bankAccountHolder,
            documentUrls: documentUrls,
          ),
        )
        as Map<String, dynamic>,
  );

  /// Sửa/nộp lại hồ sơ — dùng cả cho hồ sơ bị admin từ chối (server tự xoá rejected_at khi gọi
  /// thành công, đưa hồ sơ về lại "đang chờ xét duyệt").
  Future<Driver> updateProfile({
    required String nationalId,
    required String licenseNo,
    required String vehicleType,
    required String vehiclePlate,
    required String bankName,
    required String bankBin,
    required String bankAccountNumber,
    required String bankAccountHolder,
    List<String> documentUrls = const [],
  }) async => Driver.fromJson(
    await _api.patch(
          '/drivers/me',
          body: _profileBody(
            nationalId: nationalId,
            licenseNo: licenseNo,
            vehicleType: vehicleType,
            vehiclePlate: vehiclePlate,
            bankName: bankName,
            bankBin: bankBin,
            bankAccountNumber: bankAccountNumber,
            bankAccountHolder: bankAccountHolder,
            documentUrls: documentUrls,
          ),
        )
        as Map<String, dynamic>,
  );

  Future<void> setStatus(String status) async {
    await _api.patch('/drivers/me/status', body: {'status': status});
  }

  Future<void> setAutoAccept(bool autoAccept) async {
    await _api.patch(
      '/drivers/me/auto-accept',
      body: {'auto_accept': autoAccept},
    );
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    await _api.patch(
      '/drivers/me/location',
      body: {'latitude': latitude, 'longitude': longitude},
    );
  }

  Future<Earnings> earnings({int limit = 50}) async => Earnings.fromJson(
    await _api.get('/drivers/me/earnings', query: {'limit': limit})
        as Map<String, dynamic>,
  );

  /// Dùng để ước tính khoản trừ hoa hồng/thuế trước khi chuyến giao xong — xem
  /// hofa-db/72_driver_tax_rates.sql.
  Future<DriverFinanceSettings> financeSettings() async {
    final json = await _api.get('/driver-finance-settings');
    return json == null
        ? DriverFinanceSettings.fallback()
        : DriverFinanceSettings.fromJson(json as Map<String, dynamic>);
  }

  /// Danh sách ngân hàng admin quản lý — dropdown lúc đăng ký/sửa hồ sơ.
  Future<List<Bank>> banks() async {
    final list = await _api.get('/banks') as List;
    return list.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tài khoản ngân hàng CỦA SÀN — dùng dựng QR nạp tiền + đọc hạn mức rút tối thiểu.
  Future<BankAccountSettings> bankAccountSettings() async {
    final data = await _api.get('/bank-account-settings');
    return data == null
        ? BankAccountSettings.empty()
        : BankAccountSettings.fromJson(data as Map<String, dynamic>);
  }

  /// Trả về id của yêu cầu vừa tạo — dùng làm nội dung chuyển khoản trên QR (NAP-xxxxxxxx) để
  /// admin đối chiếu đúng yêu cầu khi xác nhận.
  Future<String> createDeposit(int amount) async {
    final data =
        await _api.post('/drivers/me/wallet/deposits', body: {'amount': amount})
            as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<void> createWithdrawal(int amount) async {
    await _api.post('/drivers/me/wallet/withdrawals', body: {'amount': amount});
  }

  /// Chuyển nội bộ 1 chiều Ví thu nhập → Ví trên — tự động ngay, không cần admin duyệt.
  Future<void> transferEarningToViTren(int amount) async {
    await _api.post(
      '/drivers/me/wallet/transfer-to-vi-tren',
      body: {'amount': amount},
    );
  }

  Future<List<WalletTransaction>> walletTransactions({
    int limit = 50,
    int offset = 0,
  }) async {
    final list =
        await _api.get(
              '/drivers/me/wallet/transactions',
              query: {'limit': limit, 'offset': offset},
            )
            as List;
    return list
        .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
