/// Dựng URL ảnh mã VietQR (img.vietqr.io) — dịch vụ ảnh QR công khai, miễn phí, không cần API
/// key, chuẩn Napas 247 nên quét được bằng hầu hết app ngân hàng ở Việt Nam. [bankBin] là mã
/// ngân hàng theo chuẩn VietQR (tra tại vietqr.io/danh-sach-ngan-hang), admin tự nhập ở web
/// admin (xem hofa_admin_app PaymentSettingsScreen).
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
