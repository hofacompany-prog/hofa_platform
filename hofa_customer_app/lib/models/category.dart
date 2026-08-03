class Category {
  final String id;
  final String? parentId;
  final String name;
  final String slug;
  final String? iconUrl;
  final String? iconName;

  Category({required this.id, this.parentId, required this.name, required this.slug, this.iconUrl, this.iconName});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        parentId: json['parent_id'] as String?,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        iconUrl: json['icon_url'] as String?,
        iconName: json['icon_name'] as String?,
      );
}

/// Danh mục riêng của cửa hàng — đây là danh mục KH thấy khi xem 1 cửa hàng, không phải
/// cây danh mục chính/con của hệ thống ở trên.
class MerchantCategory {
  final String id;
  final String merchantId;
  final String categoryId;
  final String name;
  final int sortOrder;

  MerchantCategory({
    required this.id,
    required this.merchantId,
    required this.categoryId,
    required this.name,
    required this.sortOrder,
  });

  factory MerchantCategory.fromJson(Map<String, dynamic> json) => MerchantCategory(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String? ?? '',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}
