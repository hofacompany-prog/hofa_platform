import 'dart:async';
import 'package:flutter/material.dart';
import '../repositories/order_repository.dart';

/// Icon nhắn tin kèm số nhỏ hiện số tin CHƯA ĐỌC — tự poll mỗi 10 giây, xem
/// hofa-db/75_order_chat_read_state.sql.
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

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
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
