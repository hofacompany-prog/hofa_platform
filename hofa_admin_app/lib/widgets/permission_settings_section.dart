import 'package:flutter/material.dart';
import '../core/permission_helper.dart';

/// Cho phép mở thẳng cài đặt quyền thông báo/vị trí của thiết bị ngay từ trong app — xem
/// PermissionHelper (dùng chung với popup nhắc cấp quyền lúc mở app, home_screen.dart).
class PermissionSettingsSection extends StatefulWidget {
  const PermissionSettingsSection({super.key});

  @override
  State<PermissionSettingsSection> createState() =>
      _PermissionSettingsSectionState();
}

class _PermissionSettingsSectionState
    extends State<PermissionSettingsSection> {
  PermissionState? _notificationStatus;
  PermissionState? _locationStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final notif = await PermissionHelper.notificationState();
    final loc = await PermissionHelper.locationState();
    if (mounted) {
      setState(() {
        _notificationStatus = notif;
        _locationStatus = loc;
        _loading = false;
      });
    }
  }

  Future<void> _handleNotificationTap() async {
    await PermissionHelper.requestNotification(context);
    await _refresh();
  }

  Future<void> _handleLocationTap() async {
    await PermissionHelper.requestLocation(context);
    await _refresh();
  }

  String _label(PermissionState? state) => state == PermissionState.denied
      ? 'Đã tắt — bấm để mở cài đặt'
      : 'Chưa cấp — bấm để cấp quyền';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    // Chỉ hiện Ô nào CHƯA CÓ quyền — đã cấp rồi thì ẩn hẳn, không cần chiếm chỗ màn hình nữa.
    final showNotification = _notificationStatus != PermissionState.granted;
    final showLocation = _locationStatus != PermissionState.granted;
    if (!showNotification && !showLocation) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quyền thiết bị', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (showNotification) ...[
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: ListTile(
              onTap: _handleNotificationTap,
              leading: Icon(
                Icons.notifications_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Thông báo đẩy'),
              subtitle: Text(_label(_notificationStatus)),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          if (showLocation) const SizedBox(height: 8),
        ],
        if (showLocation)
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: ListTile(
              onTap: _handleLocationTap,
              leading: Icon(
                Icons.location_on_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Vị trí'),
              subtitle: Text(_label(_locationStatus)),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }
}
