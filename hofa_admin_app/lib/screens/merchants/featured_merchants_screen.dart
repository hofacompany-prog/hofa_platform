import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/merchant.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

final _allMerchantsProvider = FutureProvider.autoDispose<List<Merchant>>(
  (ref) => ref.watch(adminRepoProvider).merchants(limit: 500),
);

/// Chọn + sắp xếp danh sách cửa hàng "nổi bật" hiện ở danh sách duyệt mặc định của trang chủ
/// app Khách — cửa hàng KHÔNG được chọn vẫn tồn tại bình thường, khách vẫn tìm/vào được qua ô
/// tìm kiếm, chỉ không nằm trong danh sách trang chủ. Xem
/// hofa-db/80_product_sort_and_featured_home.sql.
class FeaturedMerchantsScreen extends ConsumerStatefulWidget {
  const FeaturedMerchantsScreen({super.key});

  @override
  ConsumerState<FeaturedMerchantsScreen> createState() =>
      _FeaturedMerchantsScreenState();
}

class _FeaturedMerchantsScreenState
    extends ConsumerState<FeaturedMerchantsScreen> {
  final _searchCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(_allMerchantsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(Merchant m, int nextSortOrder) => _run(
    () => ref.read(adminRepoProvider).updateMerchant(m.id, {
      'featured_home': true,
      'featured_home_sort_order': nextSortOrder,
    }),
  );

  Future<void> _remove(Merchant m) => _run(
    () => ref.read(adminRepoProvider).updateMerchant(m.id, {
      'featured_home': false,
    }),
  );

  /// Đổi vị trí [m] lên/xuống 1 bậc trong [featured] (đã sắp theo thứ tự hiện tại). Ghi lại
  /// featured_home_sort_order tuần tự 0..n-1 cho cả nhóm — tự "chữa" luôn trường hợp nhiều cửa
  /// hàng cũ đang cùng sort_order (chưa từng sắp xếp) chỉ sau 1 lần bấm, giống
  /// catalog/categories_screen.dart.
  Future<void> _move(List<Merchant> featured, int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= featured.length) return;

    final reordered = List<Merchant>.from(featured);
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);

    await _run(() async {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].featuredHomeSortOrder != i) {
          await ref.read(adminRepoProvider).updateMerchant(reordered[i].id, {
            'featured_home_sort_order': i,
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final merchantsAsync = ref.watch(_allMerchantsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trang chủ nổi bật')),
      body: merchantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (all) {
          final featured = all.where((m) => m.featuredHome).toList()
            ..sort(
              (a, b) =>
                  a.featuredHomeSortOrder.compareTo(b.featuredHomeSortOrder),
            );
          final query = _searchCtrl.text.trim().toLowerCase();
          final others = all.where((m) => !m.featuredHome).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final filteredOthers = query.isEmpty
              ? others
              : others
                    .where((m) => m.name.toLowerCase().contains(query))
                    .toList();

          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chỉ cửa hàng ở danh sách bên dưới mới hiện trong danh sách duyệt mặc '
                        'định ở trang chủ app Khách — cửa hàng khác vẫn tồn tại bình thường, '
                        'khách vẫn tìm/vào được qua ô tìm kiếm.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Đang hiện ở trang chủ',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (featured.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Chưa chọn cửa hàng nào — trang chủ app Khách sẽ trống.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        ...List.generate(featured.length, (i) {
                          final m = featured[i];
                          return Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                backgroundImage: m.logoUrl != null
                                    ? NetworkImage(m.logoUrl!)
                                    : null,
                                child: m.logoUrl == null
                                    ? Icon(
                                        Icons.storefront,
                                        color: theme.colorScheme.primary,
                                      )
                                    : null,
                              ),
                              title: Text(m.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Lên',
                                    icon: const Icon(Icons.arrow_upward),
                                    onPressed: i == 0
                                        ? null
                                        : () => _move(featured, i, -1),
                                  ),
                                  IconButton(
                                    tooltip: 'Xuống',
                                    icon: const Icon(Icons.arrow_downward),
                                    onPressed: i == featured.length - 1
                                        ? null
                                        : () => _move(featured, i, 1),
                                  ),
                                  IconButton(
                                    tooltip: 'Bỏ khỏi trang chủ',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => _remove(m),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      Text(
                        'Thêm cửa hàng khác',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Tìm theo tên cửa hàng',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      if (filteredOthers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Không còn cửa hàng nào khác.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        ...filteredOthers.map(
                          (m) => Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                backgroundImage: m.logoUrl != null
                                    ? NetworkImage(m.logoUrl!)
                                    : null,
                                child: m.logoUrl == null
                                    ? Icon(
                                        Icons.storefront,
                                        color: theme.colorScheme.primary,
                                      )
                                    : null,
                              ),
                              title: Text(m.name),
                              trailing: IconButton(
                                tooltip: 'Thêm vào trang chủ',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => _add(m, featured.length),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Đang hiện ở trang chủ',
                        value: '${featured.length}',
                        icon: Icons.home_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatCard(
                        label: 'Cửa hàng khác',
                        value: '${others.length}',
                        icon: Icons.storefront_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
