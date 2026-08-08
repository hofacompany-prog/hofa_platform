import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/branch.dart';
import '../../models/order.dart' as model;
import '../../repositories/delivery_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/pickup_repository.dart';

/// Bản đồ 2 điểm (lấy hàng + giao hàng) cho 1 chuyến — mở từ màn chi tiết chuyến giao, giúp
/// tài xế hình dung quãng đường trước khi bấm "Chỉ đường" (mở app bản đồ ngoài cho chỉ đường
/// thật theo từng điểm, xem _navigate). Có vẽ 1 đường thẳng nối 2 điểm + khoảng cách chim bay
/// để tài xế ước lượng nhanh, không phải đường đi thực tế theo road network vì chưa có dịch vụ
/// định tuyến riêng. Dùng OpenStreetMap (flutter_map) như màn chọn địa chỉ ở app khách — miễn
/// phí, không cần API key, tránh vướng chi phí Google Maps ở Việt Nam.
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
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double _distance(double lat1, double lng1, double lat2, double lng2) =>
      const Distance().as(LengthUnit.Kilometer, LatLng(lat1, lng1), LatLng(lat2, lng2));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final branch = _branch;
    final hasDropoff = order?.shipLatitude != null && order?.shipLongitude != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Bản đồ chuyến giao')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Không tải được: $_error')))
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
                            _mapController.fitCamera(CameraFit.bounds(
                              bounds: LatLngBounds(
                                LatLng(branch.latitude, branch.longitude),
                                LatLng(order.shipLatitude!, order.shipLongitude!),
                              ),
                              padding: const EdgeInsets.fromLTRB(48, 80, 48, 220),
                            ));
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.hofa.hofa_driver',
                          ),
                          if (hasDropoff)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: [LatLng(branch.latitude, branch.longitude), LatLng(order.shipLatitude!, order.shipLongitude!)],
                                  color: theme.colorScheme.primary,
                                  strokeWidth: 4,
                                  pattern: const StrokePattern.dotted(),
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(branch.latitude, branch.longitude),
                                width: 44,
                                height: 44,
                                child: Icon(Icons.storefront, color: theme.colorScheme.primary, size: 36),
                              ),
                              if (hasDropoff)
                                Marker(
                                  point: LatLng(order.shipLatitude!, order.shipLongitude!),
                                  width: 44,
                                  height: 44,
                                  child: Icon(Icons.flag, color: theme.colorScheme.secondary, size: 36),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (hasDropoff)
                      Container(
                        width: double.infinity,
                        color: theme.colorScheme.primaryContainer,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.route, size: 18, color: theme.colorScheme.onPrimaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              'Khoảng cách đường chim bay: ${_distance(branch.latitude, branch.longitude, order.shipLatitude!, order.shipLongitude!).toStringAsFixed(1)} km',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
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
                              title: branch.name,
                              subtitle: branch.fullLine,
                              onNavigate: () => _navigate(branch.latitude, branch.longitude),
                            ),
                            const SizedBox(height: 8),
                            _PointRow(
                              icon: Icons.flag,
                              iconColor: theme.colorScheme.secondary,
                              title: order.shipRecipientName,
                              subtitle: order.shipFullAddress,
                              onNavigate: hasDropoff ? () => _navigate(order.shipLatitude!, order.shipLongitude!) : null,
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
                  Text(subtitle, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onNavigate != null) IconButton(icon: const Icon(Icons.directions), onPressed: onNavigate),
          ],
        ),
      ),
    );
  }
}
