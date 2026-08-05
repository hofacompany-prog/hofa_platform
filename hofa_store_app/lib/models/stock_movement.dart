/// 1 dòng lịch sử thay đổi tồn kho — chỉ để xem lại, không sửa/xoá được (xem comment bảng
/// stock_movements trong hofa-db/01_schema.sql).
class StockMovement {
  final String id;
  final String variantId;
  final String
  moveType; // purchase_in|sale_out|adjustment|transfer_in|transfer_out|return_in|damage_out
  final int quantity; // dương = vào kho, âm = ra kho
  final int balanceAfter;
  final String? referenceType;
  final String? note;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.variantId,
    required this.moveType,
    required this.quantity,
    required this.balanceAfter,
    this.referenceType,
    this.note,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: json['id'] as String,
    variantId: json['variant_id'] as String,
    moveType: json['move_type'] as String? ?? 'adjustment',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balance_after'] as num?)?.toInt() ?? 0,
    referenceType: json['reference_type'] as String?,
    note: json['note'] as String?,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );
}

const stockMoveTypeLabels = {
  'purchase_in': 'Nhập kho',
  'sale_out': 'Bán ra',
  'adjustment': 'Điều chỉnh kiểm kê',
  'transfer_in': 'Chuyển kho đến',
  'transfer_out': 'Chuyển kho đi',
  'return_in': 'Khách trả lại',
  'damage_out': 'Hư hỏng / huỷ',
};
