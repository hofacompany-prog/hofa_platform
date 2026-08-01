import '../core/api_client.dart';
import '../models/review.dart';

class ReviewRepository {
  final _api = ApiClient.instance;

  Future<List<Review>> list({required String targetType, required String targetId}) async {
    final list = await _api.get('/reviews', query: {'target_type': targetType, 'target_id': targetId}) as List;
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
