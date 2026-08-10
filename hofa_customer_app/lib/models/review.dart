class Review {
  final String id;
  final String orderId;
  final String targetType;
  final String targetId;
  final int rating;
  final String? comment;
  final String? merchantReply;
  final String? customerName;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.orderId,
    required this.targetType,
    required this.targetId,
    required this.rating,
    this.comment,
    this.merchantReply,
    this.customerName,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        orderId: json['order_id'] as String? ?? '',
        targetType: json['target_type'] as String? ?? '',
        targetId: json['target_id'] as String? ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        merchantReply: json['merchant_reply'] as String?,
        customerName: json['customer_name'] as String?,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}
