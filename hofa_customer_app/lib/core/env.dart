/// Đọc từ --dart-define-from-file=env.json lúc build/run.
/// Copy env.example.json thành env.json rồi điền giá trị thật trước khi chạy.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Domain dùng để dựng link "Chia sẻ cửa hàng" (merchant_detail_screen.dart) — KHÔNG phải
  /// domain của chính app Khách hàng (app này không có bản web/PWA công khai ở domain riêng,
  /// hofa.com.vn là trang giới thiệu tĩnh, xem hofa_landing/). store.hofa.com.vn (worker
  /// hofa-store, không còn phục vụ web quản lý cửa hàng) chỉ đóng vai trò xác thực Universal
  /// Links (iOS)/App Links (Android, xem web/.well-known/ trong hofa_store_app) + trang trung
  /// chuyển mở THẲNG app Khách hàng — xem ios/Runner/Runner.entitlements và
  /// android/app/src/main/AndroidManifest.xml (phải khớp đúng domain này).
  static const merchantShareBaseUrl = 'https://store.hofa.com.vn';
  /// Được set bằng --dart-define=APP_VERSION=<git hash> trong build_web.sh, không
  /// khai báo trong env.json — mặc định '0.1.0+1' chỉ dùng khi `flutter run` lúc dev.
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0+1',
  );

  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');

  /// Chỉ web cần — lấy ở Firebase Console > Project Settings > Cloud Messaging >
  /// Web Push certificates (Generate key pair nếu chưa có). Mobile không dùng đến.
  static const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty || apiBaseUrl.isEmpty) {
      throw StateError(
        'Thiếu cấu hình. Chạy app bằng:\n'
        'flutter run --dart-define-from-file=env.json\n'
        '(copy env.example.json thành env.json rồi điền giá trị thật trước)',
      );
    }
  }
}
