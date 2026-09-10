import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/wholesale_preorder_settings.dart';
import '../../providers/admin_providers.dart';

/// Công tắc toàn sàn ẩn/hiện "Đặt trước/Bán sỉ" ở app Khách — tắt thì mọi sản phẩm
/// sales_model='scheduled' biến mất khỏi trang chủ/tìm kiếm/chi tiết cửa hàng và tab "Đặt
/// trước" tự ẩn khỏi thanh điều hướng, không đụng tới dữ liệu sản phẩm/đơn hàng cũ. Xem
/// hofa-db/110_wholesale_preorder_toggle.sql. Chỉ 1 công tắc — tự lưu ngay khi bấm, không cần
/// nút Lưu riêng.
class WholesalePreorderSettingsScreen extends ConsumerStatefulWidget {
  const WholesalePreorderSettingsScreen({super.key});

  @override
  ConsumerState<WholesalePreorderSettingsScreen> createState() =>
      _WholesalePreorderSettingsScreenState();
}

class _WholesalePreorderSettingsScreenState
    extends ConsumerState<WholesalePreorderSettingsScreen> {
  bool _saving = false;

  Future<void> _toggle(WholesalePreorderSettings current, bool value) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepoProvider)
          .updateWholesalePreorderSettings(
            WholesalePreorderSettings(id: current.id, enabled: value),
          );
      ref.invalidate(wholesalePreorderSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Đã bật lại Đặt trước/Bán sỉ cho khách'
                  : 'Đã ẩn Đặt trước/Bán sỉ khỏi app Khách',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(wholesalePreorderSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Đặt trước / Bán sỉ')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ẩn khỏi app Khách hàng TOÀN SÀN: tab "Đặt trước" trên thanh điều hướng và '
                    'mọi sản phẩm bán theo hình thức Đặt trước/Bán sỉ (không hiện ở trang chủ, '
                    'tìm kiếm, chi tiết cửa hàng). Cửa hàng vẫn quản lý được sản phẩm loại này '
                    'bình thường — chỉ ẩn với khách, bật lại bất cứ lúc nào không mất dữ liệu.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: SwitchListTile(
                      title: const Text('Cho khách xem Đặt trước/Bán sỉ'),
                      subtitle: Text(
                        settings.enabled
                            ? 'Đang HIỆN với khách hàng'
                            : 'Đang ẨN khỏi khách hàng',
                        style: TextStyle(
                          color: settings.enabled
                              ? Colors.green
                              : theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      value: settings.enabled,
                      onChanged: _saving
                          ? null
                          : (v) => _toggle(settings, v),
                    ),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
