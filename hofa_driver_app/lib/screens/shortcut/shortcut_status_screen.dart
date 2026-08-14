import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/location_tracker.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/driver_repository.dart';

/// Đích của 2 shortcut PWA "Bật nhận đơn"/"Tắt nhận đơn" (bấm giữ icon app ở màn hình chính,
/// xem web/manifest.json) — đổi trạng thái ngay khi mở, không cần vào Trang chủ rồi tự tay
/// bấm công tắc. Cùng logic với _toggleOnline (home_screen.dart): bật cần xin quyền vị trí
/// trước, tắt thì luôn thành công. Xong việc báo trạng thái hiện tại bằng hộp thoại (không
/// dùng SnackBar vì màn này sắp bị thay bằng Trang chủ ngay sau đó, dễ mất tác dụng giữa lúc
/// điều hướng) rồi mới về Trang chủ.
class ShortcutStatusScreen extends ConsumerStatefulWidget {
  final bool goOnline;
  const ShortcutStatusScreen({super.key, required this.goOnline});

  @override
  ConsumerState<ShortcutStatusScreen> createState() =>
      _ShortcutStatusScreenState();
}

class _ShortcutStatusScreenState extends ConsumerState<ShortcutStatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  Future<void> _apply() async {
    final repo = DriverRepository();
    String message;
    try {
      if (widget.goOnline) {
        final granted = await LocationTracker.instance.ensurePermission();
        if (!granted) {
          await _finish(
            'Không bật được Online — cần cấp quyền vị trí. Mở app và bật lại ở Trang chủ.',
          );
          return;
        }
      }
      await repo.setStatus(widget.goOnline ? 'online' : 'offline');
      if (widget.goOnline) {
        // Gửi ngay 1 lần vị trí hiện tại — không đợi luồng theo dõi ở Trang chủ bắt được lần
        // di chuyển >=30m đầu tiên, giống hệt _toggleOnline (home_screen.dart).
        final pos = await LocationTracker.instance.current();
        if (pos != null) {
          try {
            await repo.updateLocation(pos.latitude, pos.longitude);
          } catch (_) {
            // luồng theo dõi ở Trang chủ sẽ tự bù ở lần cập nhật kế tiếp
          }
        }
      }
      ref.invalidate(myDriverProvider);
      message = widget.goOnline
          ? 'Bạn đang Online — sẵn sàng nhận đơn mới.'
          : 'Bạn đang Offline — tạm ngừng nhận đơn mới.';
    } catch (e) {
      message = 'Lỗi đổi trạng thái: $e';
    }
    await _finish(message);
  }

  Future<void> _finish(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trạng thái tài xế'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
