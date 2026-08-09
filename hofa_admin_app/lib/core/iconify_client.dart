import 'dart:convert';
import 'package:http/http.dart' as http;

/// 1 thư viện icon trong danh mục Iconify (api.iconify.design/collections) — [total] chỉ để
/// hiển thị tham khảo cho admin, không dùng để tính toán gì.
class IconifyCollection {
  final String prefix;
  final String name;
  final int total;
  const IconifyCollection({required this.prefix, required this.name, required this.total});
}

/// 1 icon tìm được — [prefix] để biết icon thuộc thư viện nào (hiện ở dưới tên icon cho admin
/// dễ phân biệt trùng tên giữa các thư viện khác nhau).
class IconifySearchResult {
  final String prefix;
  final String name;
  const IconifySearchResult({required this.prefix, required this.name});

  String get svgUrl => 'https://api.iconify.design/$prefix/$name.svg';
}

/// Gọi thẳng Iconify (api.iconify.design) — API công khai, miễn phí, gộp sẵn ~200 thư viện
/// icon mã nguồn mở trên GitHub (Lucide, Material Symbols, FontAwesome, Tabler, Phosphor,
/// Simple Icons...) thành 1 chỗ tìm kiếm duy nhất. Chỉ gọi từ app admin lúc admin đang duyệt/
/// tìm icon — không liên quan gì tới 3 app khách/cửa hàng/tài xế (chúng chỉ đọc URL ảnh đã
/// lưu sẵn ở Cloudinary, không bao giờ gọi Iconify).
class IconifyClient {
  static const _base = 'https://api.iconify.design';

  /// Toàn bộ danh mục thư viện Iconify — dùng cho màn "Quản lý thư viện" để admin bật/tắt.
  static Future<List<IconifyCollection>> fetchCollections() async {
    final res = await http.get(Uri.parse('$_base/collections'));
    if (res.statusCode >= 400) {
      throw Exception('Không tải được danh sách thư viện (${res.statusCode})');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = <IconifyCollection>[];
    json.forEach((prefix, value) {
      if (value is! Map<String, dynamic>) return;
      list.add(IconifyCollection(
        prefix: prefix,
        name: value['name'] as String? ?? prefix,
        total: (value['total'] as num?)?.toInt() ?? 0,
      ));
    });
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Tìm icon theo từ khoá, chỉ trong [prefixes] (thư viện admin đã bật) — không truyền
  /// prefixes coi như chưa bật thư viện nào, trả về rỗng luôn (không gọi mạng), tránh vô tình
  /// tìm tràn lan trên toàn bộ ~200 thư viện chưa được chọn dùng.
  static Future<List<IconifySearchResult>> search({
    required String query,
    required List<String> prefixes,
    int limit = 64,
  }) async {
    if (prefixes.isEmpty) return [];
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'query': query,
      'limit': '$limit',
      'prefixes': prefixes.join(','),
    });
    final res = await http.get(uri);
    if (res.statusCode >= 400) {
      throw Exception('Lỗi tìm icon (${res.statusCode})');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final icons = (json['icons'] as List? ?? []).cast<String>();
    return icons.map((id) {
      final i = id.indexOf(':');
      return IconifySearchResult(prefix: id.substring(0, i), name: id.substring(i + 1));
    }).toList();
  }

  /// Tải bytes SVG gốc của 1 icon cụ thể đã chọn — chỉ gọi ĐÚNG lúc admin bấm chọn icon đó
  /// (không tải trước cho cả danh sách), dùng để upload lên Cloudinary.
  static Future<List<int>> fetchSvgBytes(String prefix, String name) async {
    final res = await http.get(Uri.parse('$_base/$prefix/$name.svg'));
    if (res.statusCode >= 400) {
      throw Exception('Không tải được icon (${res.statusCode})');
    }
    return res.bodyBytes;
  }
}
