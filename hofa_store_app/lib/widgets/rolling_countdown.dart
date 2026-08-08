import 'dart:async';
import 'package:flutter/material.dart';

/// Đồng hồ đếm ngược tới [deadline], chữ số có hiệu ứng "chạy lên/xuống" khi đổi (xem
/// [_RollingTimeText]) — tự tick mỗi giây, không phụ thuộc widget cha có Timer riêng hay
/// không, để dùng lại được ở nhiều màn (chi tiết đơn, danh sách đơn) cùng lúc. Hết giờ thì
/// đóng băng ở 00:00 màu đỏ + dòng chữ báo trễ, KHÔNG đếm tiếp sang số âm — đúng yêu cầu chỉ
/// báo trạng thái, số phút trễ thật lưu ở order.lateMinutes khi thực sự bấm "Đã làm xong" (xem
/// routes/orders.js).
class RollingCountdown extends StatefulWidget {
  final DateTime deadline;
  final CrossAxisAlignment alignment;
  const RollingCountdown({super.key, required this.deadline, this.alignment = CrossAxisAlignment.start});

  @override
  State<RollingCountdown> createState() => _RollingCountdownState();
}

class _RollingCountdownState extends State<RollingCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = widget.deadline.difference(DateTime.now());
    final isLate = remaining.isNegative;
    final shown = isLate ? Duration.zero : remaining;
    final mm = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = shown.inSeconds.remainder(60).toString().padLeft(2, '0');
    final color = isLate ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: widget.alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RollingTimeText(
          text: '$mm:$ss',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          isLate ? 'Đơn hàng đang bị trễ' : 'Thời gian chuẩn bị còn lại',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isLate ? theme.colorScheme.error : theme.colorScheme.outline,
            fontWeight: isLate ? FontWeight.bold : null,
          ),
        ),
      ],
    );
  }
}

/// Hiệu ứng đồng hồ cơ học: từng ký tự tự trượt lên và mờ dần vào/ra riêng, dùng
/// AnimatedSwitcher keyed theo (vị trí, ký tự) — chỉ ký tự vừa đổi mới chạy hiệu ứng.
class _RollingTimeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _RollingTimeText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < text.length; i++)
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Text(text[i], key: ValueKey('$i-${text[i]}'), style: style),
            ),
          ),
      ],
    );
  }
}
