import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/maps_launcher.dart';
import '../../models/branch.dart';
import '../../models/order.dart' as model;
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';

/// Bản đồ 2 điểm (lấy hàng + giao hàng) cho 1 chuyến — mở từ màn chi tiết chuyến giao, giúp
/// tài xế hình dung quãng đường trước khi bấm "Chỉ đường" (mở app bản đồ ngoài cho chỉ đường
/// thật theo từng điểm, xem core/maps_launcher.dart#launchDirections). Đường đi + km trên bản đồ lấy từ OSRM (Open Source
/// Routing Machine, máy chủ demo công cộng router.project-osrm.org — miễn phí, không cần API
/// key, khớp hướng "tránh chi phí Google Maps" của cả dự án) theo road network thật, không
/// phải đường chim bay; nếu gọi OSRM lỗi (mất mạng, demo server quá tải) thì lùi về vẽ đường
/// thẳng + khoảng cách chim bay kèm ghi chú rõ để tài xế không hiểu nhầm là quãng đường thật.
/// Dùng OpenStreetMap (flutter_map) như màn chọn địa chỉ ở app khách.
class DeliveryMapScreen extends StatefulWidget {
  final String deliveryId;
  const DeliveryMapScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  final _mapController = MapController();
  model.Order? _order;
  Branch? _branch;
  String? _error;
  List<LatLng>? _routePoints;
  double? _routeDistanceKm;
  bool _routeIsRoad = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final delivery = await DeliveryRepository().get(widget.deliveryId);
      final order = await OrderRepository().get(delivery.orderId);
      final branch = await PickupRepository().branch(order.branchId);
      if (mounted) {
        setState(() {
          _order = order;
          _branch = branch;
        });
      }
      if (order.shipLatitude != null && order.shipLongitude != null) {
        await _fetchRoute(branch, order.shipLatitude!, order.shipLongitude!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Gọi OSRM lấy tuyến đường thật (profile "driving") giữa điểm lấy hàng và điểm giao hàng.
  /// Lỗi thì âm thầm lùi về đường thẳng — không chặn hiển thị bản đồ vì đây chỉ là gợi ý trực
  /// quan, tài xế vẫn luôn có nút "Chỉ đường" mở app bản đồ ngoài để dẫn đường thật.
  Future<void> _fetchRoute(
    Branch branch,
    double dropoffLat,
    double dropoffLng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${branch.longitude},${branch.latitude};$dropoffLng,$dropoffLat'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (body['code'] != 'Ok' || routes == null || routes.isEmpty)
        throw Exception('Không có tuyến đường');
      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map(
            (p) => LatLng(
              ((p as List)[1] as num).toDouble(),
              (p[0] as num).toDouble(),
            ),
          )
          .toList();
      final distanceKm = (route['distance'] as num) / 1000;
      if (mounted) {
        setState(() {
          _routePoints = coords;
          _routeDistanceKm = distanceKm;
          _routeIsRoad = true;
        });
        _fitToRoute();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePoints = [
            LatLng(branch.latitude, branch.longitude),
            LatLng(dropoffLat, dropoffLng),
          ];
          _routeDistanceKm = _distance(
            branch.latitude,
            branch.longitude,
            dropoffLat,
            dropoffLng,
          );
          _routeIsRoad = false;
        });
        _fitToRoute();
      }
    }
  }

  /// Route thật (đường cong theo road network) có thể vượt ra ngoài bounds thẳng 2 điểm ban
  /// đầu — canh lại khung hình sau khi có kết quả OSRM để không bị cắt đường.
  void _fitToRoute() {
    if (_routePoints == null || _routePoints!.length < 2) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_routePoints!),
          padding: const EdgeInsets.fromLTRB(48, 80, 48, 220),
        ),
      );
    } catch (_) {
      // bản đồ chưa attach (onMapReady chưa chạy) — bỏ qua, onMapReady sẽ tự canh khi sẵn sàng
    }
  }

  double _distance(double lat1, double lng1, double lat2, double lng2) =>
      const Distance().as(
        LengthUnit.Kilometer,
        LatLng(lat1, lng1),
        LatLng(lat2, lng2),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final branch = _branch;
    final hasDropoff =
        order?.shipLatitude != null && order?.shipLongitude != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Bản đồ chuyến giao')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Không tải được: $_error'),
              ),
            )
          : (branch == null || order == null)
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(branch.latitude, branch.longitude),
                      initialZoom: 14,
                      onMapReady: () {
                        if (!hasDropoff) return;
                        final bounds = _routePoints != null
                            ? LatLngBounds.fromPoints(_routePoints!)
                            : LatLngBounds(
                                LatLng(branch.latitude, branch.longitude),
                                LatLng(
                                  order.shipLatitude!,
                                  order.shipLongitude!,
                                ),
                              );
                        _mapController.fitCamera(
                          CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.fromLTRB(48, 80, 48, 220),
                          ),
                        );
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hofa.hofa_driver',
                      ),
                      if (_routePoints != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints!,
                              color: theme.colorScheme.primary,
                              strokeWidth: 4,
                              pattern: _routeIsRoad
                                  ? const StrokePattern.solid()
                                  : const StrokePattern.dotted(),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(branch.latitude, branch.longitude),
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.storefront,
                              color: theme.colorScheme.primary,
                              size: 36,
                            ),
                          ),
                          if (hasDropoff)
                            Marker(
                              point: LatLng(
                                order.shipLatitude!,
                                order.shipLongitude!,
                              ),
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.flag,
                                color: theme.colorScheme.secondary,
                                size: 36,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasDropoff && _routeDistanceKm != null)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.primaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.route,
                          size: 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _routeIsRoad
                              ? 'Quãng đường: ${_routeDistanceKm!.toStringAsFixed(1)} km'
                              : 'Khoảng cách đường chim bay: ${_routeDistanceKm!.toStringAsFixed(1)} km (chưa lấy được tuyến đường thật)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (hasDropoff)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Đang tải tuyến đường...',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PointRow(
                          icon: Icons.storefront,
                          iconColor: theme.colorScheme.primary,
                          title: branch.displayName,
                          subtitle: branch.fullLine,
                          onNavigate: () => launchDirections(
                            branch.latitude,
                            branch.longitude,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PointRow(
                          icon: Icons.flag,
                          iconColor: theme.colorScheme.secondary,
                          title: order.shipRecipientName,
                          subtitle: order.shipFullAddress,
                          onNavigate: hasDropoff
                              ? () => launchDirections(
                                  order.shipLatitude!,
                                  order.shipLongitude!,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onNavigate;

  const _PointRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onNavigate != null)
              IconButton(
                icon: const Icon(Icons.directions),
                onPressed: onNavigate,
              ),
          ],
        ),
      ),
    );
  }
}
