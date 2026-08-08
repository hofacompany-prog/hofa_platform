/// Dựng URL ảnh mã VietQR (img.vietqr.io) — dịch vụ ảnh QR công khai, miễn phí, không cần API
/// key, chuẩn Napas 247. Dùng để tài xế nạp tiền vào ví — [bankBin]/[accountNumber] ở đây là
/// TÀI KHOẢN CỦA SÀN (người nhận), lấy từ GET /bank-account-settings.
String buildVietQrUrl({
  required String bankBin,
  required String accountNumber,
  required int amount,
  required String addInfo,
  String? accountName,
}) {
  final query = {
    'amount': amount.toString(),
    'addInfo': addInfo,
    if (accountName != null && accountName.isNotEmpty) 'accountName': accountName,
  };
  final queryString = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return 'https://img.vietqr.io/image/$bankBin-$accountNumber-compact2.png?$queryString';
}
