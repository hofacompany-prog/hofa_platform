import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "đến HH:mm dd/MM" hiện kèm nhãn Tạm nghỉ khi có hẹn giờ cụ thể.
String formatBreakUntil(DateTime dt) =>
    DateFormat('HH:mm dd/MM').format(dt.toLocal());

/// Hộp thoại chọn thời lượng "Tạm nghỉ" khi bấm tắt công tắc mở cửa — bắt buộc chọn 1 mốc,
/// không cho tắt vô thời hạn từ đây (chỉ hệ thống tự đóng do không xác nhận đơn kịp mới tắt vô
/// thời hạn, xem order_detail_screen.dart _cancelDueToTimeout). Trả về null nếu người dùng Huỷ.
Future<DateTime?> pickBreakDuration(BuildContext context) async {
  final now = DateTime.now();
  final options = <String, DateTime>{
    '30 phút': now.add(const Duration(minutes: 30)),
    '1 tiếng': now.add(const Duration(hours: 1)),
    '2 tiếng': now.add(const Duration(hours: 2)),
    'Hôm nay': DateTime(now.year, now.month, now.day, 23, 59, 59),
    '7 ngày': now.add(const Duration(days: 7)),
    '30 ngày': now.add(const Duration(days: 30)),
  };

  return showDialog<DateTime>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tạm nghỉ trong bao lâu?'),
      content: SizedBox(
        width: 360,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries
              .map(
                (e) => ChoiceChip(
                  label: Text(e.key),
                  selected: false,
                  onSelected: (_) => Navigator.pop(context, e.value),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
      ],
    ),
  );
}

/// Hộp thoại xác nhận mở lại sớm khi đang Tạm nghỉ.
Future<bool> confirmReopenNow(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mở cửa lại ngay?'),
      content: const Text(
        'Huỷ trạng thái tạm nghỉ và bắt đầu nhận đơn lại ngay bây giờ.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Mở cửa'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
