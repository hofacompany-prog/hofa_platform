import 'package:flutter/material.dart';
import '../../widgets/permission_settings_section.dart';

/// Cho admin tự bật/kiểm tra quyền thông báo đẩy + vị trí của chính thiết bị đang dùng — xem
/// PermissionSettingsSection (mở thẳng cài đặt hệ thống trên bản cài native, chỉ dẫn tay trên web).
class DevicePermissionsScreen extends StatelessWidget {
  const DevicePermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quyền thiết bị')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: PermissionSettingsSection(),
          ),
        ),
      ),
    );
  }
}
