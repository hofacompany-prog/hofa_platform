/// Bản không phải web (Android/iOS) không có PWA cache lẫn app-version.json để đọc.
Future<String?> fetchDeployedVersion() async => null;

Future<void> clearCacheAndReload() async {}

Future<void> unregisterStaleServiceWorkers() async {}
