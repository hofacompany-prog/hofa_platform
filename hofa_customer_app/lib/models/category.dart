class Category {
  final String id;
  final String? parentId;
  final String name;
  final String slug;
  final String? iconUrl;

  Category({required this.id, this.parentId, required this.name, required this.slug, this.iconUrl});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        parentId: json['parent_id'] as String?,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        iconUrl: json['icon_url'] as String?,
      );
}
