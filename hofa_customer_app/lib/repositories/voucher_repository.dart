import '../core/api_client.dart';
import '../models/voucher.dart';

class VoucherRepository {
  final _api = ApiClient.instance;

  Future<VoucherValidation> validate({
    required String code,
    required String merchantId,
    required int orderAmount,
    int deliveryFee = 0,
  }) async => VoucherValidation.fromJson(
    await _api.post(
          '/vouchers/validate',
          body: {
            'code': code,
            'merchant_id': merchantId,
            'order_amount': orderAmount,
            'delivery_fee': deliveryFee,
          },
        )
        as Map<String, dynamic>,
  );
}
