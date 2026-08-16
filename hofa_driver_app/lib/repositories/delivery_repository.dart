import '../core/api_client.dart';
import '../models/delivery.dart';

class DeliveryRepository {
  final _api = ApiClient.instance;

  Future<List<Delivery>> mine({String? status, int limit = 50}) async {
    final list = await _api.get('/deliveries/mine', query: {
      if (status != null) 'status': status,
      'limit': limit,
    }) as List;
    return list.map((e) => Delivery.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Delivery> get(String id) async => Delivery.fromJson(await _api.get('/deliveries/$id') as Map<String, dynamic>);

  Future<Delivery?> byOrderId(String orderId) async {
    final json = await _api.get('/orders/$orderId/delivery') as Map<String, dynamic>?;
    return json == null ? null : Delivery.fromJson(json);
  }

  Future<Delivery> updateStatus(
    String deliveryId,
    String status, {
    String? otp,
    String? recipientName,
    List<String>? proofPhotoUrls,
    String? signatureUrl,
    String? failureReason,
  }) async =>
      Delivery.fromJson(await _api.patch('/deliveries/$deliveryId/status', body: {
        'status': status,
        if (otp != null) 'otp': otp,
        if (recipientName != null) 'recipient_name': recipientName,
        if (proofPhotoUrls != null) 'proof_photo_urls': proofPhotoUrls,
        if (signatureUrl != null) 'signature_url': signatureUrl,
        if (failureReason != null) 'failure_reason': failureReason,
      }) as Map<String, dynamic>);

  Future<bool> decline(String deliveryId) async {
    final data = await _api.post('/deliveries/$deliveryId/decline') as Map<String, dynamic>;
    return data['reassigned'] == true;
  }

  Future<void> addTrack(String deliveryId, double latitude, double longitude) async {
    await _api.post('/deliveries/$deliveryId/tracks', body: {'latitude': latitude, 'longitude': longitude});
  }

  Future<void> reportBranchClosed(String deliveryId) async {
    await _api.post('/deliveries/$deliveryId/report-branch-closed');
  }
}
