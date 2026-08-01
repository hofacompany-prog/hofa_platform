import '../core/api_client.dart';
import '../models/voucher.dart';

class VoucherRepository {
  final _api = ApiClient.instance;

  Future<VoucherValidation> validate({required String code, required String merchantId, required int orderAmount}) async =>
      VoucherValidation.fromJson(await _api.post('/vouchers/validate', body: {
        'code': code,
        'merchant_id': merchantId,
        'order_amount': orderAmount,
      }) as Map<String, dynamic>);
}
