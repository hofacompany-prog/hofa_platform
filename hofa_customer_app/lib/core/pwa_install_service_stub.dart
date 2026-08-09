/// Bản không phải web (Android/iOS cài qua store) không có khái niệm "Thêm vào màn hình
/// chính" của trình duyệt — luôn coi như đã "cài" để không hiện popup nào.
bool isStandalone() => true;

bool isIOS() => false;

bool hasDeferredPrompt() => false;

Future<String> promptInstall() async => 'unavailable';

bool wasInstalledPreviously() => false;
