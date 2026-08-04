import '../core/api_client.dart';
import '../models/voucher.dart';

class VoucherRepository {
  final _api = ApiClient.instance;

  /// Voucher công khai áp dụng được cho [merchantId] (gồm cả voucher toàn sàn) — hiện
  /// thành danh sách cho khách chọn ở màn thanh toán.
  Future<List<Voucher>> publicVouchers({required String merchantId}) async {
    final list =
        await _api.get(
              '/vouchers',
              query: {'merchant_id': merchantId, 'is_public': true},
            )
            as List;
    return list
        .map((e) => Voucher.fromJson(e as Map<String, dynamic>))
        .toList();
  }

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
