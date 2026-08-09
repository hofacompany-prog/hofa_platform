import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// 1 icon trong thư viện Lucide bundled sẵn trong app (assets/lucide_icons/) — [tags] dùng để
/// tìm kiếm, đọc từ assets/lucide_icons/manifest.json (chỉ 1 lần, cache lại trong bộ nhớ).
class LucideIconEntry {
  final String name;
  final List<String> tags;
  const LucideIconEntry({required this.name, required this.tags});

  factory LucideIconEntry.fromJson(Map<String, dynamic> json) => LucideIconEntry(
        name: json['name'] as String,
        tags: (json['tags'] as List? ?? []).map((e) => e.toString()).toList(),
      );

  String get assetPath => 'assets/lucide_icons/svg/$name.svg';
}

List<LucideIconEntry>? _cachedManifest;

Future<List<LucideIconEntry>> loadLucideManifest() async {
  if (_cachedManifest != null) return _cachedManifest!;
  final raw = await rootBundle.loadString('assets/lucide_icons/manifest.json');
  final list = jsonDecode(raw) as List;
  _cachedManifest = list.map((e) => LucideIconEntry.fromJson(e as Map<String, dynamic>)).toList();
  return _cachedManifest!;
}
