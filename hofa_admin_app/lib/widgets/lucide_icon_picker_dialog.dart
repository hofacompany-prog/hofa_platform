import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

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

/// Popup chọn 1 icon từ thư viện Lucide (mở từ đầu, bundled 100% trong app — không gọi mạng
/// ngoài lúc duyệt/tìm) — dùng cho màn Icon tabbar. Trả về tên icon (không kèm .svg) đã chọn,
/// hoặc null nếu huỷ.
Future<String?> showLucideIconPickerDialog(
  BuildContext context, {
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LucideIconPickerSheet(selected: selected),
  );
}

class _LucideIconPickerSheet extends StatefulWidget {
  final String? selected;
  const _LucideIconPickerSheet({this.selected});

  @override
  State<_LucideIconPickerSheet> createState() => _LucideIconPickerSheetState();
}

class _LucideIconPickerSheetState extends State<_LucideIconPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<LucideIconEntry>? _all;
  List<LucideIconEntry> _filtered = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await loadLucideManifest();
      if (!mounted) return;
      setState(() {
        _all = list;
        _filtered = list;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    final all = _all ?? const [];
    setState(() {
      _filtered = q.isEmpty
          ? all
          : all
              .where((e) => e.name.contains(q) || e.tags.any((t) => t.contains(q)))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn icon Lucide${_all != null ? ' (${_all!.length} icon)' : ''}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Tìm icon theo tên/từ khoá tiếng Anh, vd: cart, home, user...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: _error != null
                  ? Center(child: Text('Lỗi: $_error'))
                  : _all == null
                      ? const Center(child: CircularProgressIndicator())
                      : _filtered.isEmpty
                          ? const Center(child: Text('Không tìm thấy icon nào'))
                          : GridView.builder(
                              itemCount: _filtered.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.85,
                              ),
                              itemBuilder: (context, i) {
                                final entry = _filtered[i];
                                final isSelected = entry.name == widget.selected;
                                return InkWell(
                                  onTap: () => Navigator.pop(context, entry.name),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                                      border: isSelected ? Border.all(color: theme.colorScheme.primary) : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          entry.assetPath,
                                          width: 24,
                                          height: 24,
                                          colorFilter: ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn),
                                        ),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2),
                                          child: Text(
                                            entry.name,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
