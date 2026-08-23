import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

/// Cho phép mở thẳng cài đặt quyền thông báo/vị trí của thiết bị ngay từ trong app. Trên bản
/// cài native (Android/iOS) mở được thẳng màn Cài đặt hệ thống; trên web (PWA) trình duyệt CHẶN
/// JS tự mở bảng quyền vì lý do bảo mật — quyền CHƯA quyết định thì bật popup xin quyền của
/// trình duyệt, quyền ĐÃ bị từ chối thì chỉ dẫn tay tới đúng chỗ trong trình duyệt.
class PermissionSettingsSection extends StatefulWidget {
  const PermissionSettingsSection({super.key});

  @override
  State<PermissionSettingsSection> createState() =>
      _PermissionSettingsSectionState();
}

class _PermissionSettingsSectionState
    extends State<PermissionSettingsSection> {
  AuthorizationStatus? _notificationStatus;
  LocationPermission? _locationPermission;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    AuthorizationStatus? notif;
    LocationPermission? loc;
    try {
      notif = (await FirebaseMessaging.instance.getNotificationSettings())
          .authorizationStatus;
    } catch (_) {}
    try {
      loc = await Geolocator.checkPermission();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _notificationStatus = notif;
        _locationPermission = loc;
        _loading = false;
      });
    }
  }

  Future<bool> _tryOpenNativeSettings({required bool location}) async {
    try {
      return location
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  void _showManualInstructions(String label) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bật quyền $label'),
        content: Text(
          'Trình duyệt không cho web tự mở cài đặt quyền — bạn tự bật giúp:\n\n'
          '1. Nhấn vào biểu tượng ổ khoá (hoặc chữ "i") cạnh thanh địa chỉ trình duyệt.\n'
          '2. Chọn "Quyền của trang web" (Site settings).\n'
          '3. Bật lại quyền $label cho trang này.\n'
          '4. Tải lại trang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap() async {
    if (_notificationStatus == AuthorizationStatus.denied) {
      final opened = await _tryOpenNativeSettings(location: false);
      if (!opened && mounted) _showManualInstructions('thông báo');
      return;
    }
    await FirebaseMessaging.instance.requestPermission();
    await _refresh();
  }

  Future<void> _handleLocationTap() async {
    if (_locationPermission == LocationPermission.deniedForever) {
      final opened = await _tryOpenNativeSettings(location: true);
      if (!opened && mounted) _showManualInstructions('vị trí');
      return;
    }
    if (_locationPermission == LocationPermission.denied) {
      await Geolocator.requestPermission();
      await _refresh();
      return;
    }
    // Đã cấp quyền — vẫn cho mở cài đặt hệ thống để chỉnh sâu hơn (vd đổi "chỉ khi dùng app"
    // thành "luôn luôn" trên bản cài thật); web không mở được thì hiện hướng dẫn.
    final opened = await _tryOpenNativeSettings(location: true);
    if (!opened && mounted) _showManualInstructions('vị trí');
  }

  String get _notificationSubtitle {
    switch (_notificationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return 'Đã bật';
      case AuthorizationStatus.denied:
        return 'Đã tắt — bấm để mở cài đặt';
      default:
        return 'Chưa cấp — bấm để cấp quyền';
    }
  }

  String get _locationSubtitle {
    switch (_locationPermission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return 'Đã bật';
      case LocationPermission.deniedForever:
        return 'Đã tắt — bấm để mở cài đặt';
      case LocationPermission.denied:
        return 'Chưa cấp — bấm để cấp quyền';
      default:
        return 'Không xác định';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quyền thiết bị', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
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
            subtitle: Text(_loading ? 'Đang kiểm tra...' : _notificationSubtitle),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
        const SizedBox(height: 8),
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
            subtitle: Text(_loading ? 'Đang kiểm tra...' : _locationSubtitle),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ],
    );
  }
}
