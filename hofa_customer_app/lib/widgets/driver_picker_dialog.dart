import 'package:flutter/material.dart';
import '../models/available_driver.dart';
import '../repositories/driver_repository.dart';

/// Popup chọn tài xế cho đơn mua hộ (trượt lên từ dưới, cùng kiểu voucher_picker_dialog.dart)
/// — tự tải danh sách tài xế đang online gần [lat]/[lng] (khoảng cách tới chi nhánh), khách bấm
/// chọn 1 người. Trả về cả object AvailableDriver (không chỉ id) để nơi gọi hiện luôn tên/ảnh
/// mà không cần fetch lại; null nếu đóng mà chưa chọn. [excludeDriverIds] dùng lúc chọn LẠI sau
/// khi tài xế trước từ chối/hết hạn, để không hiện lại đúng người đó.
Future<AvailableDriver?> showDriverPickerDialog(
  BuildContext context, {
  required double lat,
  required double lng,
  List<String> excludeDriverIds = const [],
}) {
  return showModalBottomSheet<AvailableDriver>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => _DriverPickerSheet(
        lat: lat,
        lng: lng,
        excludeDriverIds: excludeDriverIds,
        scrollController: scrollController,
      ),
    ),
  );
}

class _DriverPickerSheet extends StatefulWidget {
  final double lat;
  final double lng;
  final List<String> excludeDriverIds;
  final ScrollController scrollController;

  const _DriverPickerSheet({
    required this.lat,
    required this.lng,
    required this.excludeDriverIds,
    required this.scrollController,
  });

  @override
  State<_DriverPickerSheet> createState() => _DriverPickerSheetState();
}

class _DriverPickerSheetState extends State<_DriverPickerSheet> {
  late final Future<List<AvailableDriver>> _future;

  @override
  void initState() {
    super.initState();
    _future = DriverRepository().available(lat: widget.lat, lng: widget.lng, excludeIds: widget.excludeDriverIds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Chọn tài xế', style: theme.textTheme.titleMedium),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AvailableDriver>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Lỗi: ${snapshot.error}'));
                }
                final drivers = snapshot.data ?? [];
                if (drivers.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Không có tài xế nào đang online gần cửa hàng lúc này, vui lòng thử lại sau.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  itemCount: drivers.length,
                  itemBuilder: (context, i) => _DriverTile(driver: drivers[i]),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverTile extends StatelessWidget {
  final AvailableDriver driver;
  const _DriverTile({required this.driver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: driver.avatarUrl != null ? NetworkImage(driver.avatarUrl!) : null,
              child: driver.avatarUrl == null ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(driver.fullName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 2),
                      Text(
                        driver.ratingCount > 0 ? '${driver.ratingAvg.toStringAsFixed(1)} (${driver.ratingCount})' : 'Chưa có đánh giá',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (driver.vehicleType != null) ...[
                        const SizedBox(width: 8),
                        Text('· ${driver.vehicleType}', style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                  if (driver.distanceKm != null)
                    Text(
                      '${driver.distanceKm!.toStringAsFixed(1)} km từ cửa hàng',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, driver),
              child: const Text('Chọn'),
            ),
          ],
        ),
      ),
    );
  }
}
