import 'package:intl/intl.dart';

final _vndFormat = NumberFormat.decimalPattern('vi_VN');

String formatVnd(num amount) => '${_vndFormat.format(amount)}đ';

String formatDateTime(DateTime dt) => DateFormat('HH:mm dd/MM/yyyy').format(dt.toLocal());
