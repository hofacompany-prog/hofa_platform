class InventoryItem {
  final String branchId;
  final String variantId;
  final int quantityOnHand;
  final int quantityReserved;
  final int quantityAvailable;
  final int lowStockThreshold;

  InventoryItem({
    required this.branchId,
    required this.variantId,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.quantityAvailable,
    required this.lowStockThreshold,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        branchId: json['branch_id'] as String,
        variantId: json['variant_id'] as String,
        quantityOnHand: (json['quantity_on_hand'] as num?)?.toInt() ?? 0,
        quantityReserved: (json['quantity_reserved'] as num?)?.toInt() ?? 0,
        quantityAvailable: (json['quantity_available'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt() ?? 5,
      );
}
