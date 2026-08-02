import 'package:flutter/material.dart';
import '../core/category_icons.dart';
import '../models/category.dart';
import 'network_image_box.dart';

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

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 4,
      childAspectRatio: 0.8,
      children: [
        ...visible.map((c) => CategoryTile(
              label: c.name,
              iconUrl: c.iconUrl,
              iconName: c.iconName,
              onTap: () => onTapCategory(c),
            )),
        CategoryTile(
          label: 'Xem tất cả',
          icon: Icons.grid_view_rounded,
          onTap: onTapViewAll,
        ),
      ],
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
                    : ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: NetworkImageBox(
                            url: iconUrl,
                            width: 36,
                            height: 36,
                            borderRadius: BorderRadius.circular(100),
                            fallbackIcon: Icons.category_outlined,
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
