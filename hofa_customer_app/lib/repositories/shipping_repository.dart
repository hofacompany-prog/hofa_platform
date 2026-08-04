import '../core/api_client.dart';
import '../models/shipping_fee_settings.dart';

class ShippingRepository {
  final _api = ApiClient.instance;

  Future<ShippingFeeSettings?> feeSettings() async {
    final json =
        await _api.get('/shipping-fee-settings') as Map<String, dynamic>?;
    return json == null ? null : ShippingFeeSettings.fromJson(json);
  }
}
