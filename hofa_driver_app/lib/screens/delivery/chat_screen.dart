import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/cloudinary_uploader.dart';
import '../../core/format.dart';
import '../../core/push_service.dart';
import '../../models/chat_message.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/order_repository.dart';

/// Nhắn tin khách hàng trong 1 chuyến giao — CHỈ truy cập được từ chi tiết chuyến (không có hộp
/// thư riêng). Cập nhật thời gian thực qua push FCM (PushService.chatMessageStream) — tin mới
/// tự chèn vào ngay khi push tới, không cần đợi hết vòng polling (vẫn giữ polling mỗi 5 giây
/// làm lưới an toàn). Đóng nhắn tin (window hết hạn/đơn đã huỷ) thì ẩn ô nhập, chỉ xem lại lịch
/// sử — xem hofa-db/74_order_chat.sql.
class ChatScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ChatScreen({super.key, required this.orderId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _repo = OrderRepository();
  final _bodyCtrl = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  DateTime? _otherPartyLastReadAt;
  Order? _order;
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImage = false;
  String? _error;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _pushSub;

  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _repo.get(widget.orderId).then((o) {
      if (mounted) setState(() => _order = o);
    });
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
    PushService.instance.setOpenChat(widget.orderId);
    _pushSub = PushService.instance.chatMessageStream.listen((data) {
      if (data['order_id'] == widget.orderId) _load(silent: true);
    });
  }

  @override
  void dispose() {
    PushService.instance.setOpenChat(null);
    _pushSub?.cancel();
    _pollTimer?.cancel();
    _bodyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final (messages, otherPartyLastReadAt) = await _repo.chatMessages(
        widget.orderId,
        ChatChannel.customerDriver,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _otherPartyLastReadAt = otherPartyLastReadAt;
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
      await _repo.sendChatMessage(
        widget.orderId,
        ChatChannel.customerDriver,
        body: body?.trim(),
        imageUrl: imageUrl,
      );
      _bodyCtrl.clear();
      await _load(silent: true);
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
    final chatSettingsAsync = ref.watch(chatSettingsProvider);
    final order = _order;
    final canSend =
        order != null &&
        isChatWindowOpen(
          status: order.status,
          deliveredAt: order.deliveredAt,
          hoursAfterDelivered:
              chatSettingsAsync.valueOrNull?.hoursAfterDelivered ?? 1,
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          order != null ? 'Nhắn tin · ${order.orderCode}' : 'Nhắn tin',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                ? Center(child: Text(_error!))
                : _messages.isEmpty
                ? const Center(child: Text('Chưa có tin nhắn nào'))
                : Builder(
                    builder: (context) {
                      final items = _timelineItems(_messages);
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          if (item is DateTime) {
                            return _DateSeparator(date: item);
                          }
                          final message = item as ChatMessage;
                          return _MessageBubble(
                            message: message,
                            isMe: message.senderId == _myUserId,
                            otherPartyLastReadAt: _otherPartyLastReadAt,
                          );
                        },
                      );
                    },
                  ),
          ),
          if (order == null)
            const SizedBox()
          else if (!canSend)
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
  // Mốc "đã đọc tới lúc nào" của đầu bên kia — chỉ dùng cho tin CỦA MÌNH (isMe), để hiện
  // 1 tick (đã gửi)/2 tick (đã xem) thay vì giờ. Tin nhận từ đối phương vẫn hiện giờ (không
  // còn kèm ngày — ngày đã tách ra _DateSeparator riêng).
  final DateTime? otherPartyLastReadAt;
  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.otherPartyLastReadAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    // Đầu bên kia đã mở màn chat SAU (hoặc đúng lúc) tin này được gửi thì coi là đã xem — 1
    // tick (Icons.done) = đã gửi, 2 tick (Icons.done_all) = đã xem, giống quy ước quen thuộc.
    final seen =
        otherPartyLastReadAt != null &&
        !message.createdAt.isAfter(otherPartyLastReadAt!);
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
            if (isMe)
              Icon(
                seen ? Icons.done_all : Icons.done,
                size: 14,
                color: textColor.withValues(alpha: seen ? 1 : 0.7),
              )
            else
              Text(
                // Chỉ giờ — ngày đã tách riêng thành _DateSeparator ở giữa màn hình, không lặp
                // lại ở từng tin nữa.
                formatTime(message.createdAt),
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

/// Mốc chuyển ngày giữa 2 tin nhắn khác ngày — pill nhỏ căn giữa màn hình, cùng kiểu
/// WhatsApp/Messenger, xem _timelineItems.
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _dateSeparatorLabel(date),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Hôm nay"/"Hôm qua" cho 2 ngày gần nhất, còn lại hiện dd/MM/yyyy — [date] đã chuẩn hoá về
/// đúng nửa đêm giờ local (xem _timelineItems), không cần gọi .toLocal() lại ở đây.
String _dateSeparatorLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return formatDate(date);
}

/// Chèn 1 mốc DateTime (nửa đêm giờ local của ngày đó) trước tin đầu tiên của mỗi ngày khác
/// nhau — ListView.itemBuilder phân biệt DateTime (mốc ngày) và ChatMessage (bong bóng tin) qua
/// kiểu runtime, xem chỗ dùng ở build().
List<Object> _timelineItems(List<ChatMessage> messages) {
  final items = <Object>[];
  DateTime? lastDay;
  for (final m in messages) {
    final local = m.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (lastDay == null || day != lastDay) {
      items.add(day);
      lastDay = day;
    }
    items.add(m);
  }
  return items;
}
