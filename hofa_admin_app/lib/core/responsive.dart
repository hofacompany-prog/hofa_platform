import 'package:flutter/material.dart';

/// Bề rộng nội dung dialog "co giãn" — hầu hết dialog trong app này đặt cứng
/// `SizedBox(width: 320-480)` cho `AlertDialog.content`, chỉ hợp với desktop/tablet. Trên điện
/// thoại (viewport hẹp hơn [preferred] + khoảng đệm 2 bên mà AlertDialog tự chừa), SizedBox
/// cứng đó khiến dialog tràn ra ngoài màn hình thay vì tự co lại. Dùng hàm này thay cho việc
/// gán thẳng số vào `SizedBox(width: ...)` để dialog luôn vừa màn hình, giữ nguyên [preferred]
/// trên màn rộng.
double dialogWidth(BuildContext context, double preferred) {
  // 48 = khoảng đệm 2 bên tối thiểu muốn chừa lại quanh dialog trên màn hẹp.
  final available = MediaQuery.sizeOf(context).width - 48;
  return available < preferred ? available.clamp(200, preferred) : preferred;
}
