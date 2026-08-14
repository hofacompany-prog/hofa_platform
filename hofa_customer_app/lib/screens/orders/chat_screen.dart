import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cloudinary_uploader.dart';
import '../../core/format.dart';
import '../../models/chat_message.dart';
import '../../providers/app_providers.dart';

/// Nhắn tin trong 1 đơn hàng — CHỈ truy cập được từ chi tiết đơn (không có hộp thư riêng). Tải
/// lại bằng polling (không có hạ tầng realtime) — mở màn tự tải lại mỗi 5 giây trong lúc đang
/// mở, dừng khi rời màn. Đóng nhắn tin (window hết hạn/đơn đã huỷ) thì ẩn ô nhập, chỉ xem lại
/// lịch sử — xem hofa-db/74_order_chat.sql.
class ChatScreen extends ConsumerStatefulWidget {
  final String orderId;
  final ChatChannel channel;
  final String title;

  const ChatScreen({
    super.key,
    required this.orderId,
    required this.channel,
    required this.title,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _bodyCtrl = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImage = false;
  String? _error;
  Timer? _pollTimer;

  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bodyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final messages = await ref
          .read(orderRepoProvider)
          .chatMessages(widget.orderId, widget.channel);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted && !silent) setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _send({String? body, String? imageUrl}) async {
    if ((body == null || body.trim().isEmpty) && imageUrl == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(orderRepoProvider)
          .sendChatMessage(
            widget.orderId,
            widget.channel,
            body: body?.trim(),
            imageUrl: imageUrl,
          );
      _bodyCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;
    setState(() => _uploadingImage = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await CloudinaryUploader().uploadImage(
        bytes,
        file.name,
        folder: 'chat',
      );
      await _send(imageUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tải ảnh lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final chatSettingsAsync = ref.watch(chatSettingsProvider);
    // Mặc định BẮT BUỘC còn mở (an toàn) trong lúc chưa tải xong order/chat-settings — tránh
    // hiện ô nhập rồi bị chặn ở POST vì thật ra đã đóng.
    final canSend =
        orderAsync.valueOrNull != null &&
        isChatWindowOpen(
          status: orderAsync.value!.status,
          deliveredAt: orderAsync.value!.deliveredAt,
          hoursAfterDelivered:
              chatSettingsAsync.valueOrNull?.hoursAfterDelivered ?? 1,
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                ? Center(child: Text(_error!))
                : _messages.isEmpty
                ? const Center(child: Text('Chưa có tin nhắn nào'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _MessageBubble(
                      message: _messages[i],
                      isMe: _messages[i].senderId == _myUserId,
                    ),
                  ),
          ),
          if (!canSend)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                'Đã đóng nhắn tin — quá thời gian cho phép.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: _uploadingImage
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      onPressed: _uploadingImage ? null : _pickAndSendImage,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _bodyCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Nhập tin nhắn...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) => _send(body: v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      onPressed: _sending
                          ? null
                          : () => _send(body: _bodyCtrl.text),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  width: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 200,
                    height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            if (message.body != null && message.body!.isNotEmpty) ...[
              if (message.imageUrl != null) const SizedBox(height: 6),
              Text(message.body!, style: TextStyle(color: textColor)),
            ],
            const SizedBox(height: 4),
            Text(
              formatDateTime(message.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
