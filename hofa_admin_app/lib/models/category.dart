class Category {
  final String id;
  final String? parentId;
  final String name;
  final String slug;
  final String? iconUrl;
  final String? iconName;
  final int sortOrder;

  Category({
    required this.id,
    this.parentId,
    required this.name,
    required this.slug,
    this.iconUrl,
    this.iconName,
    this.sortOrder = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        parentId: json['parent_id'] as String?,
        name: json['name'] as String,
        slug: json['slug'] as String,
        iconUrl: json['icon_url'] as String?,
        iconName: json['icon_name'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// Danh mục riêng của cửa hàng — nằm dưới 1 danh mục con hệ thống ([Category] có
/// [Category.parentId] khác null). Khách xem trang cửa hàng chỉ thấy danh mục này. Khác
/// [Category] (danh mục hệ thống, admin quản lý ở catalog/categories_screen.dart) — bảng
/// riêng merchant_categories, xem hofa_store_app/lib/models/category.dart (bản gốc).
class MerchantCategory {
  final String id;
  final String merchantId;
  final String categoryId;
  final String name;
  final int sortOrder;
  final bool isActive;

  MerchantCategory({
    required this.id,
    required this.merchantId,
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });

  factory MerchantCategory.fromJson(Map<String, dynamic> json) => MerchantCategory(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}
