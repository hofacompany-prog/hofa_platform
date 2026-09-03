import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

/// Xử lý link "Chia sẻ cửa hàng" (merchant_detail_screen.dart) mở thẳng vào app:
/// - Universal Links/App Links (https://hofa.com.vn/merchants/...) thường tự mở app TRƯỚC KHI
///   engine kịp chạy tới đây — vẫn lắng nghe để chắc chắn điều hướng đúng route, không phụ thuộc
///   suy luận route ngầm của go_router từ URI gốc.
/// - Custom scheme "hofa://open?path=..." (trang trung chuyển hofa_landing/public/index.html
///   dùng khi Universal Links không được tôn trọng, vd trình duyệt trong Zalo/Messenger) — path
///   đích nằm trong query param "path", không suy được trực tiếp từ path của chính URI này (host
///   "open" chiếm mất vị trí "merchants" nếu viết dạng hofa://merchants/slug), nên cần tự đọc
///   query param rồi điều hướng tay bằng router.go().
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init(GoRouter router) async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(router, initial);
    } catch (_) {
      // không lấy được initial link — bỏ qua, app vẫn mở bình thường vào màn mặc định
    }
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handle(router, uri),
      onError: (_) {},
    );
  }

  void dispose() {
    _sub?.cancel();
  }

  void _handle(GoRouter router, Uri uri) {
    String? path;
    if (uri.scheme == 'hofa') {
      path = uri.queryParameters['path'];
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      path = uri.path;
      if (uri.hasQuery) path = '$path?${uri.query}';
    }
    if (path == null || path.isEmpty || path == '/') return;
    router.go(path);
  }
}
