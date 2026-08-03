import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/location_tracker.dart';
import '../../models/delivery.dart';
import '../../providers/auth_provider.dart';
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/driver_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _repo = DriverRepository();
  bool _busy = false;
  String? _locationError;
  String? _lastSyncedStatus;

  void _syncTrackingWithStatus(String status) {
    final shouldTrack = status == 'online' || status == 'busy';
    if (shouldTrack && !LocationTracker.instance.isTracking) {
      LocationTracker.instance.start((pos) async {
        try {
          await _repo.updateLocation(pos.latitude, pos.longitude);
        } catch (_) {
          // mất mạng tạm thời — bỏ qua, lần cập nhật tiếp theo sẽ tự bù
        }
        // Đang có chuyến chạy dở — ghi thêm vệt đường để khách/cửa hàng theo dõi trên bản đồ.
        final active = ref.read(activeDeliveryProvider).valueOrNull;
        if (active != null && !kTerminalDeliveryStatuses.contains(active.status)) {
          try {
            await DeliveryRepository().addTrack(active.id, pos.latitude, pos.longitude);
          } catch (_) {
            // tương tự — bỏ qua, không chặn UI vì 1 lần ghi vệt đường lỗi
          }
        }
      }).then((ok) {
        if (!ok && mounted) setState(() => _locationError = 'Cần cấp quyền vị trí để nhận đơn gần bạn');
      });
    } else if (!shouldTrack && LocationTracker.instance.isTracking) {
      LocationTracker.instance.stop();
    }
  }

  Future<void> _toggleOnline(bool goOnline) async {
    setState(() => _busy = true);
    try {
      if (goOnline) {
        final granted = await LocationTracker.instance.ensurePermission();
        if (!granted) {
          setState(() => _locationError = 'Cần cấp quyền vị trí để bật chế độ online');
          return;
        }
      }
      await _repo.setStatus(goOnline ? 'online' : 'offline');
      if (goOnline) {
        // Gửi ngay 1 lần vị trí hiện tại — không đợi luồng theo dõi bắt được lần di
        // chuyển >=30m đầu tiên, vì lúc đó server chưa có toạ độ nên chưa tìm thấy
        // tài xế này khi có đơn mới.
        final pos = await LocationTracker.instance.current();
        if (pos != null) {
          try {
            await _repo.updateLocation(pos.latitude, pos.longitude);
          } catch (_) {
            // luồng theo dõi bên dưới sẽ tự bù ở lần cập nhật kế tiếp
          }
        }
      }
      ref.invalidate(myDriverProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoAccept(bool value) async {
    setState(() => _busy = true);
    try {
      await _repo.setAutoAccept(value);
      ref.invalidate(myDriverProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverAsync = ref.watch(myDriverProvider);
    final activeDeliveryAsync = ref.watch(activeDeliveryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text('HOFA Tài xế', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myDriverProvider);
          ref.invalidate(activeDeliveryProvider);
        },
        child: driverAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (driver) {
            if (driver == null) return const Center(child: Text('Chưa có hồ sơ tài xế'));
            final isOnline = driver.status == 'online' || driver.status == 'busy';
            final hasActiveDelivery = driver.status == 'busy';

            if (_lastSyncedStatus != driver.status) {
              _lastSyncedStatus = driver.status;
              WidgetsBinding.instance.addPostFrameCallback((_) => _syncTrackingWithStatus(driver.status));
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  color: isOnline ? theme.colorScheme.primary.withValues(alpha: 0.10) : theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isOnline ? Icons.circle : Icons.circle_outlined,
                                color: isOnline ? Colors.green : Colors.grey, size: 14),
                            const SizedBox(width: 8),
                            Text(
                              hasActiveDelivery ? 'Đang chạy đơn' : (isOnline ? 'Đang online' : 'Đang offline'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          driver.isVerified ? 'Hồ sơ đã được duyệt' : 'Hồ sơ đang chờ HOFA duyệt',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: driver.isVerified ? null : theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Bật nhận đơn (online)'),
                          value: isOnline,
                          onChanged: (_busy || hasActiveDelivery) ? null : _toggleOnline,
                        ),
                        if (hasActiveDelivery)
                          Text('Hoàn thành chuyến hiện tại trước khi tắt online',
                              style: theme.textTheme.bodySmall),
                        const Divider(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Tự động nhận đơn'),
                          subtitle: const Text('Bật: hệ thống tự gán đơn gần nhất, không cần xác nhận.\nTắt: bạn xem và chấp nhận từng đơn.'),
                          value: driver.autoAccept,
                          onChanged: _busy ? null : _toggleAutoAccept,
                        ),
                        if (_locationError != null) ...[
                          const SizedBox(height: 8),
                          Text(_locationError!, style: TextStyle(color: theme.colorScheme.error)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                activeDeliveryAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, _) => const SizedBox(),
                  data: (delivery) => delivery == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.outline),
                                const SizedBox(height: 12),
                                Text(isOnline ? 'Đang chờ đơn mới...' : 'Bật online để bắt đầu nhận đơn',
                                    style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        )
                      : _ActiveDeliveryCard(delivery: delivery),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActiveDeliveryCard extends StatelessWidget {
  final Delivery delivery;
  const _ActiveDeliveryCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondary.withValues(alpha: 0.12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(deliveryStatusLabels[delivery.status] ?? delivery.status,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text([
            if (delivery.distanceKm != null) '${delivery.distanceKm!.toStringAsFixed(1)} km',
            formatVnd(delivery.driverFee),
          ].join(' · ')),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/deliveries/${delivery.id}'),
      ),
    );
  }
}
