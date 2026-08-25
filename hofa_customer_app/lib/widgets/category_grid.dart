import 'package:flutter/material.dart';
import '../core/category_icons.dart';
import '../models/category.dart';

const _maxTiles = 8; // 2 hàng x 4 cột — ô cuối luôn dành cho "Xem tất cả"

/// Lưới danh mục lớn (2 hàng x 4 cột), ô cuối cùng luôn là "Xem tất cả" dẫn sang màn
/// danh sách đầy đủ. [categories] phải là danh sách đã lọc sẵn (vd chỉ danh mục gốc,
/// hoặc chỉ danh mục con của 1 danh mục cha) — widget này không tự lọc theo parentId.
class CategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<Category> onTapCategory;
  final VoidCallback onTapViewAll;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.onTapCategory,
    required this.onTapViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox();

    final visible = categories.take(_maxTiles - 1).toList();

    // maxCrossAxisExtent + mainAxisExtent cố định kích thước ô tuyệt đối (không phụ
    // thuộc bề rộng container) — trên web/màn hình rộng chỉ hiện thêm cột chứ ô không
    // bị giãn to ra như GridView.count(crossAxisCount cố định) từng bị.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visible.length + 1,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 84,
        mainAxisExtent: 100,
        mainAxisSpacing: 12,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, i) {
        if (i == visible.length) {
          return CategoryTile(label: 'Xem tất cả', icon: Icons.grid_view_rounded, onTap: onTapViewAll);
        }
        final c = visible[i];
        return CategoryTile(
          label: c.name,
          iconUrl: c.iconUrl,
          iconName: c.iconName,
          onTap: () => onTapCategory(c),
        );
      },
    );
  }
}

class CategoryTile extends StatelessWidget {
  final String label;
  final String? iconUrl;
  final String? iconName;
  final IconData? icon;
  final VoidCallback onTap;

  const CategoryTile({super.key, required this.label, this.iconUrl, this.iconName, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: icon != null
                ? Icon(icon, color: theme.colorScheme.primary)
                : (iconName != null && iconName!.isNotEmpty)
                    ? Icon(categoryIconOf(iconName), color: theme.colorScheme.primary)
                    : (iconUrl != null && iconUrl!.isNotEmpty)
                        // Icon từ thư viện (Lucide/Online, xem widgets/icon_picker_dialog.dart ở
                        // admin) là ảnh nét đơn sắc — KHÔNG dùng NetworkImageBox (dành cho ảnh
                        // thật, BoxFit.cover, không tô màu) vì nó khiến icon hiện đúng màu gốc
                        // rasterize (thường ra đen) thay vì xanh thương hiệu, và cover làm icon
                        // trông to hơn hẳn icon Material bên cạnh (glyph Material vốn có sẵn
                        // đệm, vẽ nhỏ hơn khung — icon thư viện vẽ gần sát viền).
                        ? Transform.scale(
                            scale: 0.5,
                            child: Image.network(
                              iconUrl!,
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                              color: theme.colorScheme.primary,
                              colorBlendMode: BlendMode.srcIn,
                              errorBuilder: (_, _, _) =>
                                  Icon(Icons.category_outlined, color: theme.colorScheme.primary),
                            ),
                          )
                        : Icon(Icons.category_outlined, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
