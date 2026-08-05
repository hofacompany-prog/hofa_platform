import '../core/api_client.dart';
import '../models/inventory_item.dart';
import '../models/stock_movement.dart';

class InventoryRepository {
  final _api = ApiClient.instance;

  Future<List<InventoryItem>> list(String branchId) async {
    final list = await _api.get('/branches/$branchId/inventory') as List;
    return list
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> adjust({
    required String branchId,
    required String variantId,
    required String moveType,
    required int quantity,
    String? note,
  }) async {
    final data =
        await _api.post(
              '/inventory/adjust',
              body: {
                'branch_id': branchId,
                'variant_id': variantId,
                'move_type': moveType,
                'quantity': quantity,
                if (note != null && note.isNotEmpty) 'note': note,
              },
            )
            as Map<String, dynamic>;
    return (data['balance_after'] as num).toInt();
  }

  Future<void> updateLowStockThreshold({
    required String branchId,
    required String variantId,
    required int lowStockThreshold,
  }) async {
    await _api.patch(
      '/branches/$branchId/inventory/$variantId',
      body: {'low_stock_threshold': lowStockThreshold},
    );
  }

  /// Xoá hẳn 1 dòng tồn kho — server tự chặn nếu đang giữ chỗ cho đơn hàng chưa giao
  /// (ném lỗi rõ ràng bằng tiếng Việt, hiển thị lại nguyên văn cho chủ cửa hàng).
  Future<void> delete({
    required String branchId,
    required String variantId,
  }) async {
    await _api.delete('/branches/$branchId/inventory/$variantId');
  }

  Future<List<StockMovement>> movements({
    required String branchId,
    String? variantId,
    int limit = 50,
  }) async {
    final list =
        await _api.get(
              '/branches/$branchId/stock-movements',
              query: {
                'limit': limit,
                if (variantId != null) 'variant_id': variantId,
              },
            )
            as List;
    return list
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
