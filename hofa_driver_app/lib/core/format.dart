import 'package:intl/intl.dart';

final _vndFormat = NumberFormat.decimalPattern('vi_VN');

String formatVnd(num amount) => '${_vndFormat.format(amount)}đ';

String formatDateTime(DateTime dt) => DateFormat('HH:mm dd/MM/yyyy').format(dt.toLocal());

String formatDate(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt.toLocal());

String formatTime(DateTime dt) => DateFormat('HH:mm').format(dt.toLocal());

/// Tên quán đứng trước tên chi nhánh (vd "Trà Sữa ABC - Chi nhánh Quận 1") — tài xế cần thấy
/// tên quán để nhận ra cửa hàng, tên chi nhánh để biết đúng địa điểm nếu quán có nhiều chi
/// nhánh. Bỏ phần chi nhánh nếu trùng tên quán (quán chỉ có 1 chi nhánh, đặt tên y hệt) để
/// khỏi lặp.
String pickupTitle(String? merchantName, String branchName) {
  if (merchantName == null || merchantName.trim().isEmpty) return branchName;
  if (merchantName.trim().toLowerCase() == branchName.trim().toLowerCase()) return merchantName;
  return '$merchantName - $branchName';
}
