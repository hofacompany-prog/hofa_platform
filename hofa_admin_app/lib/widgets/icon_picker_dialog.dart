import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/iconify_client.dart';
import '../core/lucide_manifest.dart';
import '../providers/admin_providers.dart';
import '../screens/settings/icon_library_manager_screen.dart';

/// Popup chọn 1 icon — 2 nguồn: "Có sẵn" (thư viện Lucide bundled trong app, duyệt/tìm hoàn
/// toàn offline) và "Thư viện online" (tìm qua Iconify, chỉ trong các thư viện admin đã bật ở
/// màn Quản lý thư viện). Trả về bytes SVG gốc + tên file gợi ý để nơi gọi tự upload lên
/// Cloudinary — nơi gọi không cần biết icon đến từ nguồn nào.
Future<({Uint8List bytes, String filename})?> showIconPickerDialog(BuildContext context) {
  return showModalBottomSheet<({Uint8List bytes, String filename})>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _IconPickerSheet(),
  );
}

class _IconPickerSheet extends ConsumerStatefulWidget {
  const _IconPickerSheet();

  @override
  ConsumerState<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends ConsumerState<_IconPickerSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickLucide(String name) async {
    final bytes = (await rootBundle.load('assets/lucide_icons/svg/$name.svg')).buffer.asUint8List();
    if (mounted) Navigator.pop(context, (bytes: bytes, filename: '$name.svg'));
  }

  Future<void> _pickIconify(IconifySearchResult r) async {
    try {
      final bytes = await IconifyClient.fetchSvgBytes(r.prefix, r.name);
      if (mounted) {
        Navigator.pop(context, (bytes: Uint8List.fromList(bytes), filename: '${r.prefix}-${r.name}.svg'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Có sẵn (Lucide)'), Tab(text: 'Thư viện online')],
            ),
            SizedBox(
              height: 480,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _LucideTab(onPicked: _pickLucide),
                  _IconifyTab(onPicked: _pickIconify),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LucideTab extends StatefulWidget {
  final ValueChanged<String> onPicked;
  const _LucideTab({required this.onPicked});

  @override
  State<_LucideTab> createState() => _LucideTabState();
}

class _LucideTabState extends State<_LucideTab> {
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
          : all.where((e) => e.name.contains(q) || e.tags.any((t) => t.contains(q))).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Tìm icon theo tên/từ khoá, vd: cart, home, user...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          Expanded(
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
                              return InkWell(
                                onTap: () => widget.onPicked(entry.name),
                                borderRadius: BorderRadius.circular(12),
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
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _IconifyTab extends ConsumerStatefulWidget {
  final ValueChanged<IconifySearchResult> onPicked;
  const _IconifyTab({required this.onPicked});

  @override
  ConsumerState<_IconifyTab> createState() => _IconifyTabState();
}

class _IconifyTabState extends ConsumerState<_IconifyTab> {
  final _searchCtrl = TextEditingController();
  List<IconifySearchResult>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(List<String> prefixes) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await IconifyClient.search(query: q, prefixes: prefixes);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final libraries = ref.watch(iconLibrariesProvider).valueOrNull ?? const [];
    final prefixes = libraries.map((l) => l.prefix).toList();

    if (libraries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_add_outlined, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'Chưa bật thư viện icon online nào',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IconLibraryManagerScreen()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Quản lý thư viện icon'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Tìm icon online, vd: cart, home, user...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(prefixes),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quản lý thư viện icon',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IconLibraryManagerScreen()),
                ),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${libraries.length} thư viện đang bật — bấm nút bánh răng để thêm/bớt',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Lỗi: $_error'))
                    : _results == null
                        ? Center(
                            child: Text(
                              'Gõ từ khoá rồi nhấn Enter để tìm',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                            ),
                          )
                        : _results!.isEmpty
                            ? const Center(child: Text('Không tìm thấy icon nào'))
                            : GridView.builder(
                                itemCount: _results!.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.85,
                                ),
                                itemBuilder: (context, i) {
                                  final r = _results![i];
                                  return InkWell(
                                    onTap: () => widget.onPicked(r),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.network(
                                          r.svgUrl,
                                          width: 24,
                                          height: 24,
                                          colorFilter: ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn),
                                          placeholderBuilder: (_) => const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(strokeWidth: 1.5),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2),
                                          child: Text(
                                            r.name,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }
}
