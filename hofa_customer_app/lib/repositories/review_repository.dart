import '../core/api_client.dart';
import '../models/review.dart';

class ReviewRepository {
  final _api = ApiClient.instance;

  Future<List<Review>> list({
    required String targetType,
    required String targetId,
    int? rating,
    int limit = 20,
    int offset = 0,
  }) async {
    final list = await _api.get('/reviews', query: {
      'target_type': targetType,
      'target_id': targetId,
      'limit': limit,
      'offset': offset,
      if (rating != null) 'rating': rating,
    }) as List;
    return list.map((e) => Review.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Mọi đánh giá (mọi target_type) của 1 đơn — dùng ở màn chi tiết đơn để biết đã đánh giá
  /// món/cửa hàng/tài xế nào rồi, tránh hiện lại ô nhập cho mục đã gửi.
  Future<List<Review>> listByOrder(String orderId) async {
    final list = await _api.get('/reviews', query: {'order_id': orderId}) as List;
    return list.map((e) => Review.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Review> create({
    required String orderId,
    required String targetType,
    required String targetId,
    required int rating,
    String? comment,
  }) async =>
      Review.fromJson(await _api.post('/reviews', body: {
        'order_id': orderId,
        'target_type': targetType,
        'target_id': targetId,
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }) as Map<String, dynamic>);
}
