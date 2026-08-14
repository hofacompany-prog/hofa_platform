import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chat_settings.dart';
import '../../providers/admin_providers.dart';

/// Số giờ được nhắn tin thêm sau khi đơn giao xong (khách hàng ↔ tài xế, khách hàng ↔ cửa
/// hàng) — xem hofa-db/74_order_chat.sql. Trong lúc đơn còn đang vận hành thì luôn mở, không
/// tính giờ này.
class ChatSettingsScreen extends ConsumerStatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  ConsumerState<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends ConsumerState<ChatSettingsScreen> {
  final _hoursCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _hoursCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(ChatSettings s) {
    _hoursCtrl.text = s.hoursAfterDelivered.toString();
  }

  Future<void> _save(ChatSettings current) async {
    final hours = int.tryParse(_hoursCtrl.text.trim());
    if (hours == null || hours < 0) {
      _showError('Số giờ không hợp lệ');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(adminRepoProvider)
          .updateChatSettings(
            ChatSettings(id: current.id, hoursAfterDelivered: hours),
          );
      ref.invalidate(chatSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cấu hình nhắn tin')),
        );
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(chatSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nhắn tin trong đơn')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) {
          if (!_initialized) {
            _fillFrom(settings);
            _initialized = true;
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khách hàng nhắn tin được với tài xế và với cửa hàng ngay trong chi tiết '
                      'đơn hàng, không có hộp thư riêng. Trong lúc đơn còn đang vận hành (chưa '
                      'huỷ/hoàn tiền) luôn mở — sau khi giao xong, chỉ mở thêm đúng số giờ dưới '
                      'đây rồi tự ẩn hẳn lối vào nhắn tin.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mở thêm sau khi giao xong',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _hoursCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                suffixText: 'giờ',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mặc định 1 giờ. Đặt 0 nếu muốn đóng nhắn tin ngay khi đơn giao xong.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(settings),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lưu cấu hình'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
