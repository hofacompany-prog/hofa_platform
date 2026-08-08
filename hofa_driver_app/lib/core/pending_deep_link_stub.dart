/// Bản không phải web (Android/iOS) không cần cơ chế này — getInitialMessage() của
/// firebase_messaging đã đủ tin cậy trên native, không có kiểu WebAPK bỏ qua URL lúc mở lại.
Future<String?> readAndClearPendingDeepLink() async => null;

void setPendingDeepLinkMessageHandler(void Function() callback) {}
