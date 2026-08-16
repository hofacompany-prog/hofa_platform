import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "đến HH:mm dd/MM" hiện kèm nhãn Tạm nghỉ khi có hẹn giờ cụ thể.
String formatBreakUntil(DateTime dt) =>
    DateFormat('HH:mm dd/MM').format(dt.toLocal());

/// Hộp thoại chọn thời lượng "Đóng cửa tạm thời" khi admin chọn mode Đóng cửa ở màn Giờ mở
/// cửa — bắt buộc chọn 1 mốc (không cho đóng vô thời hạn), cùng bộ lựa chọn với
/// hofa_store_app/lib/widgets/branch_break_dialogs.dart để admin và chủ cửa hàng thấy nhất
/// quán. Dùng khi admin duyệt báo cáo "quán đóng cửa" từ tài xế
/// (server/src/routes/deliveries.js POST /deliveries/:id/report-branch-closed) và tự quyết
/// định đóng cửa quán đó trong bao lâu. Trả về null nếu người dùng Huỷ.
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
      title: const Text('Đóng cửa tạm thời trong bao lâu?'),
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
