import 'dart:math';

/// Khoảng cách đường chim bay giữa 2 toạ độ (km) — công thức Haversine, cùng công thức
/// server dùng để ghép tài xế gần nhất (server/src/utils.js#haversineKm), dùng lại ở đây
/// để ước tính phí ship khớp với cách backend sẽ tính khi nối vào đơn hàng thật.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Hiện khoảng cách ngắn gọn cạnh thời gian chuẩn bị — dưới 1km hiện theo mét cho dễ hình
/// dung (vd "800m"), từ 1km trở lên làm tròn 1 số lẻ (vd "3.2km").
String formatDistanceKm(double km) {
  if (km < 1) return '${(km * 1000).round()}m';
  return '${km.toStringAsFixed(1)}km';
}
