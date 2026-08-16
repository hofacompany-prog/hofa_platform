import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Tự thêm dấu chấm phân cách hàng nghìn khi gõ số tiền VNĐ (không có số lẻ) — gõ "1000000"
/// hiện ngay "1.000.000", dễ đếm số 0 hơn. Cùng cách format với formatVnd() (core/format.dart),
/// chỉ khác là formatVnd() dùng để HIỂN THỊ (đã có "đ" ở cuối), còn formatter này dùng để GÕ
/// (không có "đ", cursor tự điều chỉnh theo đúng vị trí đang gõ).
class VndInputFormatter extends TextInputFormatter {
  static final RegExp _nonDigits = RegExp(r'[^0-9]');
  static final NumberFormat _format = NumberFormat.decimalPattern('vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_nonDigits, '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final digitsBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(_nonDigits, '')
        .length;

    final formatted = _format.format(int.parse(digits));

    var seen = 0;
    var offset = formatted.length;
    for (var i = 0; i < formatted.length; i++) {
      if (!_nonDigits.hasMatch(formatted[i])) {
        seen++;
        if (seen == digitsBeforeCursor) {
          offset = i + 1;
          break;
        }
      }
    }
    if (digitsBeforeCursor <= 0) offset = 0;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Text đang gõ (có dấu chấm) → số nguyên VNĐ thật, null nếu rỗng/không hợp lệ. Dùng thay
  /// int.tryParse(controller.text) ở mọi nơi field này đang gắn formatter này.
  static int? parse(String text) {
    final digits = text.replaceAll(_nonDigits, '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  /// Điền sẵn giá trị có dấu chấm cho TextEditingController lúc mở form sửa (initial value) —
  /// dùng thay value.toString().
  static String display(num? value) =>
      value == null ? '' : _format.format(value);
}
