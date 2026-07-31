import '../core/api_client.dart';
import '../models/inventory_item.dart';

class InventoryRepository {
  final _api = ApiClient.instance;

  Future<List<InventoryItem>> list(String branchId) async {
    final list = await _api.get('/branches/$branchId/inventory') as List;
    return list.map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> adjust({
    required String branchId,
    required String variantId,
    required String moveType,
    required int quantity,
    String? note,
  }) async {
    final data = await _api.post('/inventory/adjust', body: {
      'branch_id': branchId,
      'variant_id': variantId,
      'move_type': moveType,
      'quantity': quantity,
      if (note != null && note.isNotEmpty) 'note': note,
    }) as Map<String, dynamic>;
    return (data['balance_after'] as num).toInt();
  }
}
