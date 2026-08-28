import 'dart:async';
import 'package:flutter/material.dart';
import '../core/push_service.dart';
import '../repositories/order_repository.dart';

/// Icon nhắn tin kèm số nhỏ hiện số tin CHƯA ĐỌC — poll mỗi 10 giây làm lưới an toàn, cộng
/// thêm tải lại ngay khi có push tin nhắn mới tới đúng đơn/kênh này (PushService.chatMessageStream)
/// để số hiện đúng ngay lập tức thay vì đợi tới vòng poll kế — xem hofa-db/75_order_chat_read_state.sql.
class ChatBadgeIcon extends StatefulWidget {
  final String orderId;
  final String channel; // 'customer_driver' | 'customer_merchant'
  final IconData icon;

  const ChatBadgeIcon({
    super.key,
    required this.orderId,
    required this.channel,
    required this.icon,
  });

  @override
  State<ChatBadgeIcon> createState() => _ChatBadgeIconState();
}

class _ChatBadgeIconState extends State<ChatBadgeIcon> {
  int _count = 0;
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _pushSub;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    _pushSub = PushService.instance.chatMessageStream.listen((data) {
      if (data['order_id'] == widget.orderId &&
          data['channel'] == widget.channel) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final counts = await OrderRepository().chatUnreadCounts(widget.orderId);
      if (mounted) setState(() => _count = counts[widget.channel] ?? 0);
    } catch (_) {
      // badge chỉ là tiện ích hiển thị — lỗi mạng thoáng qua không cần báo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Badge(
      label: Text('$_count'),
      isLabelVisible: _count > 0,
      child: Icon(widget.icon),
    );
  }
}
