import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/iconify_client.dart';
import '../../providers/admin_providers.dart';

/// Bật/tắt thư viện icon Iconify (~200 thư viện mã nguồn mở trên GitHub) để dùng ở tab
/// "Thư viện online" của popup chọn icon (màn Icon tabbar) — chỉ ảnh hưởng tới việc tìm kiếm
/// sau này, không đụng gì tới icon đã chọn/lưu trước đó.
class IconLibraryManagerScreen extends ConsumerStatefulWidget {
  const IconLibraryManagerScreen({super.key});

  @override
  ConsumerState<IconLibraryManagerScreen> createState() => _IconLibraryManagerScreenState();
}

class _IconLibraryManagerScreenState extends ConsumerState<IconLibraryManagerScreen> {
  final _searchCtrl = TextEditingController();
  List<IconifyCollection>? _all;
  List<IconifyCollection> _filtered = const [];
  String? _error;
  final Set<String> _busyPrefixes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await IconifyClient.fetchCollections();
      if (!mounted) return;
      setState(() {
        _all = list;
        _filtered = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    final all = _all ?? const [];
    setState(() {
      _filtered = q.isEmpty
          ? all
          : all.where((c) => c.name.toLowerCase().contains(q) || c.prefix.contains(q)).toList();
    });
  }

  Future<void> _toggle(IconifyCollection c, bool enable) async {
    setState(() => _busyPrefixes.add(c.prefix));
    try {
      if (enable) {
        await ref.read(adminRepoProvider).enableIconLibrary(c.prefix, c.name);
      } else {
        await ref.read(adminRepoProvider).disableIconLibrary(c.prefix);
      }
      ref.invalidate(iconLibrariesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyPrefixes.remove(c.prefix));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledAsync = ref.watch(iconLibrariesProvider);
    final enabledPrefixes = enabledAsync.valueOrNull?.map((e) => e.prefix).toSet() ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý thư viện icon')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bật thư viện nào thì thư viện đó xuất hiện trong tìm kiếm ở tab '
                      '"Thư viện online" khi chọn icon.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Tìm thư viện theo tên, vd: material, tabler, fontawesome...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _error != null
                    ? Center(child: Text('Lỗi: $_error'))
                    : _all == null
                        ? const Center(child: CircularProgressIndicator())
                        : _filtered.isEmpty
                            ? const Center(child: Text('Không tìm thấy thư viện nào'))
                            : ListView.builder(
                                itemCount: _filtered.length,
                                itemBuilder: (context, i) {
                                  final c = _filtered[i];
                                  final enabled = enabledPrefixes.contains(c.prefix);
                                  final busy = _busyPrefixes.contains(c.prefix);
                                  return ListTile(
                                    title: Text(c.name),
                                    subtitle: Text('${c.prefix} · ${c.total} icon'),
                                    trailing: busy
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Switch(
                                            value: enabled,
                                            onChanged: (v) => _toggle(c, v),
                                          ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
