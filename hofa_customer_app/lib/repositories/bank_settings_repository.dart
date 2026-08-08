import '../core/api_client.dart';
import '../models/bank_account_settings.dart';

class BankSettingsRepository {
  final _api = ApiClient.instance;

  Future<BankAccountSettings> get() async {
    final data = await _api.get('/bank-account-settings');
    return data == null
        ? BankAccountSettings.empty()
        : BankAccountSettings.fromJson(data as Map<String, dynamic>);
  }
}
