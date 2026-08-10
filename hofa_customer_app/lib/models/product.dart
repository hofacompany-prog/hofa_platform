import 'product_variant.dart';

class Product {
  final String id;
  final String merchantId;
  final String? merchantCategoryId;
  final String name;
  final String? description;
  final String salesModel; // instant | scheduled
  final String status;
  final String? brand;
  final String unit;
  final List<String> images;
  final List<String> tags;
  final bool isFeatured;
  final double ratingAvg;
  final int ratingCount;
  final int soldCount;
  final List<ProductVariant> variants;
  // Km từ chi nhánh gần nhất của cửa hàng bán sản phẩm này tới toạ độ khách đang xem — null nếu
  // server không nhận được lat/lng. Xem GET /products (server/src/routes/products.js#attachDistance).
  final double? distanceKm;
  // true nếu distanceKm vượt bán kính giao hàng RIÊNG của chi nhánh gần nhất (nhưng vẫn trong
  // mức mặc định toàn sàn, nếu không sản phẩm đã bị ẩn hẳn khỏi danh sách) — dùng tô cam
  // distanceKm khi hiển thị, xem hofa-db/61_delivery_radius_settings.sql.
  final bool beyondOwnRadius;

  Product({
    required this.id,
    required this.merchantId,
    this.merchantCategoryId,
    required this.name,
    this.description,
    required this.salesModel,
    required this.status,
    this.brand,
    required this.unit,
    required this.images,
    required this.tags,
    required this.isFeatured,
    required this.ratingAvg,
    required this.ratingCount,
    required this.soldCount,
    required this.variants,
    this.distanceKm,
    this.beyondOwnRadius = false,
  });

  ProductVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    for (final v in variants) {
      if (v.isDefault) return v;
    }
    return variants.first;
  }

  bool get isWholesale => salesModel == 'scheduled';

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String? ?? '',
    merchantCategoryId: json['merchant_category_id'] as String?,
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    salesModel: json['sales_model'] as String? ?? 'instant',
    status: json['status'] as String? ?? 'active',
    brand: json['brand'] as String?,
    unit: json['unit'] as String? ?? 'cái',
    images: (json['images'] as List? ?? []).map((e) => e.toString()).toList(),
    tags: (json['tags'] as List? ?? []).map((e) => e.toString()).toList(),
    isFeatured: json['is_featured'] as bool? ?? false,
    // NUMERIC ở Postgres về qua node-postgres là String, không phải num.
    ratingAvg: (num.tryParse('${json['rating_avg']}') ?? 0).toDouble(),
    ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
    variants: (json['variants'] as List? ?? [])
        .map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
        .toList(),
    distanceKm: json['distance_km'] != null
        ? num.tryParse('${json['distance_km']}')?.toDouble()
        : null,
    beyondOwnRadius: json['beyond_own_radius'] as bool? ?? false,
  );
}
