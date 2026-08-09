import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cloudinary_uploader.dart';
import '../../core/nav_tab_slots.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/icon_picker_dialog.dart';
import 'icon_library_manager_screen.dart';

/// Chọn icon tabbar tuỳ chỉnh cho từng tab của cả 4 app (admin/customer/store/driver) — icon
/// lấy từ thư viện Lucide bundled sẵn trong app này hoặc tìm online qua Iconify (xem
/// widgets/icon_picker_dialog.dart), chọn xong tải lên Cloudinary rồi lưu URL vào
/// nav_tab_icons (GET/PUT /nav-icons) để app tương ứng tự đọc lúc khởi động. Không chọn thì
/// tab đó giữ nguyên icon Material mặc định trong code app đó, không có gì bị ảnh hưởng.
class NavIconsScreen extends ConsumerStatefulWidget {
  const NavIconsScreen({super.key});

  @override
  ConsumerState<NavIconsScreen> createState() => _NavIconsScreenState();
}

class _NavIconsScreenState extends ConsumerState<NavIconsScreen> {
  final Set<String> _busyKeys = {};

  String _key(String app, String tabKey) => '$app::$tabKey';

  Future<void> _pickIcon(String app, String tabKey) async {
    final picked = await showIconPickerDialog(context);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _busyKeys.add(_key(app, tabKey)));
    try {
      final secureUrl = await CloudinaryUploader().uploadImage(
        picked.bytes,
        picked.filename,
        folder: 'nav_icons',
      );
      final pngUrl = toCloudinaryPngUrl(secureUrl);
      await ref.read(adminRepoProvider).setNavIcon(app, tabKey, pngUrl);
      ref.invalidate(navIconsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật icon')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyKeys.remove(_key(app, tabKey)));
    }
  }

  Future<void> _resetIcon(String app, String tabKey) async {
    setState(() => _busyKeys.add(_key(app, tabKey)));
    try {
      await ref.read(adminRepoProvider).setNavIcon(app, tabKey, null);
      ref.invalidate(navIconsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyKeys.remove(_key(app, tabKey)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navIconsAsync = ref.watch(navIconsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Icon tabbar'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IconLibraryManagerScreen()),
            ),
            icon: const Icon(Icons.tune),
            label: const Text('Quản lý thư viện icon'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: navIconsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (rows) {
          final byKey = {
            for (final r in rows) _key(r.app, r.tabKey): r.iconUrl,
          };
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chọn icon từ thư viện Lucide cho từng tab điều hướng của 4 app. '
                        'Tab chưa chọn icon riêng sẽ giữ nguyên icon mặc định.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final app in navTabSlots.keys) ...[
                        Text(
                          navAppLabels[app] ?? app,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLow,
                          child: Column(
                            children: navTabSlots[app]!.map((slot) {
                              final key = _key(app, slot.tabKey);
                              final iconUrl = byKey[key];
                              final busy = _busyKeys.contains(key);
                              return ListTile(
                                leading: iconUrl != null
                                    ? Image.network(
                                        iconUrl,
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.contain,
                                        color: theme.colorScheme.primary,
                                        colorBlendMode: BlendMode.srcIn,
                                        errorBuilder: (_, _, _) => Icon(
                                          slot.icon,
                                          color: theme.colorScheme.outline,
                                        ),
                                      )
                                    : Icon(
                                        slot.icon,
                                        color: theme.colorScheme.outline,
                                      ),
                                title: Text(slot.label),
                                subtitle: iconUrl != null
                                    ? const Text('Đang dùng icon tuỳ chỉnh')
                                    : const Text('Icon mặc định'),
                                trailing: busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (iconUrl != null)
                                            TextButton(
                                              onPressed: () =>
                                                  _resetIcon(app, slot.tabKey),
                                              child: const Text('Khôi phục mặc định'),
                                            ),
                                          OutlinedButton(
                                            onPressed: () =>
                                                _pickIcon(app, slot.tabKey),
                                            child: const Text('Chọn icon'),
                                          ),
                                        ],
                                      ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
