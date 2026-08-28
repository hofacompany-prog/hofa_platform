import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/location_tracker.dart';
import '../../core/permission_helper.dart';
import '../../models/delivery.dart';
import '../../providers/auth_provider.dart';
import '../../providers/delivery_providers.dart';
import '../../repositories/delivery_repository.dart';
import '../../repositories/driver_repository.dart';
import '../../widgets/notification_bell.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _repo = DriverRepository();
  bool _busy = false;
  String? _locationError;
  String? _lastSyncedStatus;
  bool _permDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kiểm tra NGAY lúc mở màn chính — tài xế thiếu 1 trong 2 quyền này thì không nhận được đơn
    // mới (thông báo) hoặc không tìm được (vị trí). Hỏi lại mỗi lần vào Trang chủ tới khi được
    // cấp đủ, nhưng có nút "Để sau" để không bị kẹt nếu chưa muốn cấp ngay (khác trước đây bắt
    // buộc, không có lối thoát).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureRequiredPermissions(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Quay lại app sau khi mở Cài đặt hệ thống bật quyền — tự kiểm tra lại ngay, đóng dialog chặn
  // nếu đã cấp đủ, khỏi bắt bấm thêm gì trong app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensureRequiredPermissions();
  }

  Future<void> _ensureRequiredPermissions() async {
    final notif = await PermissionHelper.notificationState();
    final loc = await PermissionHelper.locationState();
    if (!mounted) return;
    if (notif == PermissionState.granted && loc == PermissionState.granted) {
      if (_permDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }
    if (_permDialogOpen) return;
    _permDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cần cấp quyền để nhận đơn'),
        content: const Text(
          'Tài xế nên bật Thông báo và Vị trí để nhận đơn mới kịp thời và xác định đúng vị trí '
          'giao hàng — bấm "Cấp quyền" để tiếp tục. Nếu trước đó đã từ chối, nút này sẽ mở thẳng '
          'Cài đặt để bạn bật lại. Chưa muốn cấp ngay thì bấm "Để sau", lần sau vào Trang chủ sẽ '
          'hỏi lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () async {
              await PermissionHelper.requestNotification(dialogContext);
              if (dialogContext.mounted) {
                await PermissionHelper.requestLocation(dialogContext);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) await _ensureRequiredPermissions();
            },
            child: const Text('Cấp quyền'),
          ),
        ],
      ),
    );
    _permDialogOpen = false;
  }

  void _syncTrackingWithStatus(String status) {
    final shouldTrack = status == 'online' || status == 'busy';
    if (shouldTrack && !LocationTracker.instance.isTracking) {
      LocationTracker.instance.start((pos) async {
        try {
          await _repo.updateLocation(pos.latitude, pos.longitude);
        } catch (_) {
          // mất mạng tạm thời — bỏ qua, lần cập nhật tiếp theo sẽ tự bù
        }
        // Đang có (những) chuyến chạy dở — ghi thêm vệt đường cho TỪNG chuyến để khách/cửa hàng
        // theo dõi trên bản đồ (tài xế Dự phòng có thể có nhiều hơn 1 chuyến cùng lúc).
        final active = ref.read(activeDeliveriesProvider).valueOrNull ?? const [];
        for (final d in active) {
          if (kTerminalDeliveryStatuses.contains(d.status) || d.status == 'assigned') continue;
          try {
            await DeliveryRepository().addTrack(d.id, pos.latitude, pos.longitude);
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
    // Tài xế THƯỜNG tối đa 1 phần tử; tài xế Dự phòng (is_backup_driver) có thể có nhiều chuyến
    // cùng lúc — xem activeDeliveriesProvider.
    final activeDeliveriesAsync = ref.watch(activeDeliveriesProvider);
    final theme = Theme.of(context);
    final activeDeliveries = activeDeliveriesAsync.valueOrNull ?? const [];
    // "Đơn đang chờ xác nhận" ở nút AppBar vẫn chỉ mở ĐÚNG 1 màn /offer/:id tại 1 thời điểm
    // (route chỉ nhận 1 deliveryId) — lấy lời mời chưa xác nhận ĐẦU TIÊN nếu có nhiều.
    final pendingOffer = activeDeliveries
        .cast<Delivery?>()
        .firstWhere((d) => d?.status == 'assigned', orElse: () => null);
    final hasPendingOffer = pendingOffer != null;

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
        actions: [
          // Luôn hiện (khác _PendingOfferCard bên dưới chỉ hiện khi CÓ đơn đang chờ) — bấm vào
          // lúc không có đơn thì báo rõ ràng thay vì im lặng không làm gì, tránh cảm giác "nút
          // không hoạt động".
          IconButton(
            tooltip: 'Đơn đang chờ xác nhận',
            icon: hasPendingOffer
                ? Badge(backgroundColor: theme.colorScheme.error, child: const Icon(Icons.pending_actions))
                : const Icon(Icons.pending_actions),
            onPressed: () {
              if (hasPendingOffer) {
                context.push('/offer/${pendingOffer.id}');
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Hiện không có đơn nào đang chờ xác nhận.')));
              }
            },
          ),
          const NotificationBell(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myDriverProvider);
          ref.invalidate(activeDeliveriesProvider);
        },
        child: driverAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (driver) {
            if (driver == null) return const Center(child: Text('Chưa có hồ sơ tài xế'));
            final isOnline = driver.status == 'online' || driver.status == 'busy';
            // driver.status='busy' KHÔNG dùng được nữa để suy ra "đang chạy đơn" — tài xế Dự
            // phòng (is_backup_driver) được gán đơn mà KHÔNG bị chuyển sang busy (xem
            // hofa-db/98_backup_driver_pool.sql), vẫn giữ 'online' dù đang chạy. Suy thẳng từ
            // danh sách chuyến đang hoạt động (bỏ qua 'assigned' — mời chưa xác nhận, chưa thật
            // sự "đang chạy") mới đúng cho cả 2 loại tài xế.
            final hasActiveDelivery = activeDeliveries.any(
              (d) => d.status != 'assigned',
            );

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
                          driver.isVerified
                              ? 'Hồ sơ đã được duyệt'
                              : (driver.isRejected ? 'Hồ sơ bị từ chối' : 'Hồ sơ đang chờ HOFA duyệt'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: driver.isVerified ? null : theme.colorScheme.error,
                          ),
                        ),
                        if (driver.isRejected) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Lý do: ${driver.rejectionReason ?? "—"}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.push('/edit-driver-profile'),
                              child: const Text('Sửa hồ sơ'),
                            ),
                          ),
                        ],
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
                          subtitle: const Text(
                              'Màn nhận đơn luôn hiện khi có đơn mới. Bật: thanh trượt chạy nhanh rồi tự nhận hộ.\n'
                              'Tắt: thanh trượt chạy lâu hơn, hết giờ chưa trượt thì đơn chuyển tài xế khác.'),
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
                activeDeliveriesAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, _) => const SizedBox(),
                  data: (deliveries) => deliveries.isEmpty
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
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chuyến đầu tiên (nhận trước nhất) — thẻ đầy đủ như cũ.
                            // 'assigned' = đơn đã gán nhưng CHƯA xác nhận (OfferScreen,
                            // /offer/:id) — khác các trạng thái sau đó (đã nhận, đang chạy) mở
                            // /deliveries/:id. Có nút riêng ở đây phòng khi lỡ push (không bấm
                            // vào thông báo kịp) vẫn có cách quay lại đúng màn xác nhận thay vì
                            // phải chờ push tới lần nữa.
                            deliveries.first.status == 'assigned'
                                ? _PendingOfferCard(delivery: deliveries.first)
                                : _ActiveDeliveryCard(delivery: deliveries.first),
                            // Tài xế Dự phòng có thể nhận thêm đơn dù đang chạy đơn khác — tách
                            // hẳn thành 1 danh sách RIÊNG bên dưới cho đơn thứ 2, 3... thay vì
                            // trộn chung 1 thẻ, để không nhầm là cùng 1 chuyến.
                            if (deliveries.length > 1) ...[
                              const SizedBox(height: 20),
                              Text(
                                'Các đơn khác đang chạy (${deliveries.length - 1})',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final d in deliveries.skip(1)) ...[
                                _OtherDeliveryTile(delivery: d),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Đơn đã gán nhưng chưa xác nhận — nút mở thẳng OfferScreen (/offer/:id), chỗ dựa khi lỡ bấm
/// vào push thông báo (thông báo bị tắt, hoặc trình duyệt/thiết bị chặn) nhưng đơn vẫn đang
/// chờ, không phải chờ push tới lần nữa mới thấy lại được.
class _PendingOfferCard extends ConsumerWidget {
  final Delivery delivery;
  const _PendingOfferCard({required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orderCode = ref
        .watch(orderForDeliveryProvider(delivery.orderId))
        .valueOrNull
        ?.orderCode;
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    orderCode != null
                        ? 'Đơn $orderCode đang chờ xác nhận!'
                        : 'Bạn có 1 đơn đang chờ xác nhận!',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (delivery.pickupDisplayName != null) ...[
              const SizedBox(height: 6),
              Text(
                delivery.pickupDisplayName!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              [
                if (delivery.distanceKm != null) '${delivery.distanceKm!.toStringAsFixed(1)} km',
                formatVnd(delivery.driverFee),
              ].join(' · '),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: theme.colorScheme.secondary),
                onPressed: () => context.push('/offer/${delivery.id}'),
                child: const Text('Mở màn xác nhận'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveDeliveryCard extends ConsumerWidget {
  final Delivery delivery;
  const _ActiveDeliveryCard({required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orderCode = ref
        .watch(orderForDeliveryProvider(delivery.orderId))
        .valueOrNull
        ?.orderCode;
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondary.withValues(alpha: 0.12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          [
            ?orderCode,
            deliveryStatusLabels[delivery.status] ?? delivery.status,
          ].join(' · '),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (delivery.pickupDisplayName != null) Text(delivery.pickupDisplayName!, style: theme.textTheme.bodyMedium),
              Text([
                if (delivery.distanceKm != null) '${delivery.distanceKm!.toStringAsFixed(1)} km',
                formatVnd(delivery.driverFee),
              ].join(' · ')),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/deliveries/${delivery.id}'),
      ),
    );
  }
}

/// 1 dòng gọn cho đơn thứ 2, 3... ở danh sách RIÊNG "Các đơn khác đang chạy" (khác hẳn thẻ chính
/// _ActiveDeliveryCard/_PendingOfferCard phía trên) — vẫn hiện mã đơn để phân biệt rõ ràng.
class _OtherDeliveryTile extends ConsumerWidget {
  final Delivery delivery;
  const _OtherDeliveryTile({required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orderCode = ref
        .watch(orderForDeliveryProvider(delivery.orderId))
        .valueOrNull
        ?.orderCode;
    final isPending = delivery.status == 'assigned';
    return Card(
      elevation: 0,
      color: isPending
          ? theme.colorScheme.secondary.withValues(alpha: 0.7)
          : theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        dense: true,
        leading: Icon(
          isPending ? Icons.notifications_active : Icons.local_shipping_outlined,
          color: isPending ? Colors.white : theme.colorScheme.secondary,
        ),
        title: Text(
          orderCode ?? 'Đang tải...',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isPending ? Colors.white : null,
          ),
        ),
        subtitle: Text(
          isPending
              ? 'Đang chờ xác nhận'
              : (deliveryStatusLabels[delivery.status] ?? delivery.status),
          style: TextStyle(color: isPending ? Colors.white : null),
        ),
        trailing: Icon(Icons.chevron_right, color: isPending ? Colors.white : null),
        onTap: () => context.push(
          isPending ? '/offer/${delivery.id}' : '/deliveries/${delivery.id}',
        ),
      ),
    );
  }
}
