/// Dựng URL ảnh mã VietQR (img.vietqr.io) — dịch vụ ảnh QR công khai, miễn phí, không cần API
/// key, chuẩn Napas 247 nên quét được bằng hầu hết app ngân hàng ở Việt Nam. Dùng để admin xem
/// mã chuyển khoản trả tài xế lúc duyệt yêu cầu rút ví — [bankBin]/[accountNumber] ở đây là của
/// TÀI XẾ (người nhận), khác với QR ở app khách (của sàn, người nhận là sàn).
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
