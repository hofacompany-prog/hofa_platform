/// Đọc từ --dart-define-from-file=env.json lúc build/run.
/// Copy env.example.json thành env.json rồi điền giá trị thật trước khi chạy.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Gốc URL app Khách đã deploy — dùng để dựng link chia sẻ (vd chia sẻ 1 cửa hàng, xem
  /// merchant_detail_screen.dart). KHÔNG lấy từ Uri.base vì app này còn có bản Android native
  /// (không có "URL trình duyệt" để đọc). Domain riêng hofa.com.vn đã gắn sẵn cho worker
  /// hofa-customer (xác nhận qua app-version.json khớp nhau ở cả 2 domain).
  static const webBaseUrl = 'https://hofa.com.vn';
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
