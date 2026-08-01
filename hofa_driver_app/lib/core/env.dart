/// Đọc từ --dart-define-from-file=env.json lúc build/run.
/// Copy env.example.json thành env.json rồi điền giá trị thật trước khi chạy.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

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
