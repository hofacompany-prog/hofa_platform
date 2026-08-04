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

  /// Số voucher tối đa được áp dụng cùng lúc trên 1 đơn (admin cấu hình) — mặc định 1
  /// nếu server chưa có dòng cấu hình nào.
  Future<int> maxVouchersPerOrder() async {
    final data = await _api.get('/voucher-settings');
    if (data == null) return 1;
    return ((data as Map<String, dynamic>)['max_vouchers_per_order'] as num?)
            ?.toInt() ??
        1;
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
