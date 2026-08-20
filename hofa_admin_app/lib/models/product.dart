class ProductVariant {
  final String id;
  final String productId;
  final String? sku;
  final String name;
  final int price;
  final int? comparePrice;
  final int? costPrice;
  final int? wholesalePrice;
  final bool isDefault;
  final bool isActive;

  ProductVariant({
    required this.id,
    required this.productId,
    this.sku,
    required this.name,
    required this.price,
    this.comparePrice,
    this.costPrice,
    this.wholesalePrice,
    required this.isDefault,
    required this.isActive,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
    id: json['id'] as String,
    productId: json['product_id'] as String? ?? '',
    sku: json['sku'] as String?,
    name: json['name'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    comparePrice: (json['compare_price'] as num?)?.toInt(),
    costPrice: (json['cost_price'] as num?)?.toInt(),
    wholesalePrice: (json['wholesale_price'] as num?)?.toInt(),
    isDefault: json['is_default'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
  );
}

/// Bậc giá theo số lượng của 1 biến thể. minDaysPerWeek == 0 nghĩa là bậc "Giá sỉ" (chỉ
/// 1 điều kiện số lượng, dùng đúng 1 giá unitPrice). minDaysPerWeek > 0 nghĩa là bậc
/// "Đặt trước" — có 2 điều kiện độc lập: số lượng (tổng phần cùng 1 lần giao) và số
/// ngày/tuần khách đặt RIÊNG sản phẩm này — 3 giá tương ứng: chỉ đạt số lượng (unitPrice),
/// chỉ đạt số ngày (unitPriceDays), đạt cả 2 (unitPriceBoth).
class WholesaleTier {
  final String id;
  final String variantId;
  final int minQuantity;
  final int? maxQuantity;
  final int unitPrice;
  final int minDaysPerWeek;
  final int? unitPriceDays;
  final int? unitPriceBoth;
  // Chỉ áp dụng cho bậc giá sỉ (minDaysPerWeek = 0) — điều kiện THAY THẾ theo tổng số
  // lượng cả đơn (mọi sản phẩm cộng lại): đạt 1 trong 2 (số lượng riêng món HOẶC số
  // lượng cả đơn) là được giá bậc này.
  final int? minOrderQuantity;

  WholesaleTier({
    required this.id,
    required this.variantId,
    required this.minQuantity,
    this.maxQuantity,
    required this.unitPrice,
    required this.minDaysPerWeek,
    this.unitPriceDays,
    this.unitPriceBoth,
    this.minOrderQuantity,
  });

  factory WholesaleTier.fromJson(Map<String, dynamic> json) => WholesaleTier(
    id: json['id'] as String,
    variantId: json['variant_id'] as String? ?? '',
    minQuantity: (json['min_quantity'] as num?)?.toInt() ?? 0,
    maxQuantity: (json['max_quantity'] as num?)?.toInt(),
    unitPrice: (json['unit_price'] as num?)?.toInt() ?? 0,
    minDaysPerWeek: (json['min_days_per_week'] as num?)?.toInt() ?? 0,
    unitPriceDays: (json['unit_price_days'] as num?)?.toInt(),
    unitPriceBoth: (json['unit_price_both'] as num?)?.toInt(),
    minOrderQuantity: (json['min_order_quantity'] as num?)?.toInt(),
  );
}

class Product {
  final String id;
  final String merchantId;
  final String? merchantCategoryId;
  final String name;
  final String? description;
  final String salesModel;
  final String status;
  final String unit;
  final String? variantGroupName;
  final List<String> images;
  final List<ProductVariant> variants;
  // Thứ tự hiển thị cho khách ở màn chi tiết cửa hàng — cửa hàng tự sắp xếp ở màn danh sách sản
  // phẩm, xem hofa-db/80_product_sort_and_featured_home.sql.
  final int sortOrder;

  Product({
    required this.id,
    required this.merchantId,
    this.merchantCategoryId,
    required this.name,
    this.description,
    required this.salesModel,
    required this.status,
    required this.unit,
    this.variantGroupName,
    required this.images,
    required this.variants,
    this.sortOrder = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    merchantId: json['merchant_id'] as String,
    merchantCategoryId: json['merchant_category_id'] as String?,
    name: json['name'] as String,
    description: json['description'] as String?,
    salesModel: json['sales_model'] as String? ?? 'instant',
    status: json['status'] as String? ?? 'draft',
    unit: json['unit'] as String? ?? 'cái',
    variantGroupName: json['variant_group_name'] as String?,
    images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
    variants:
        (json['variants'] as List?)
            ?.map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );

  int get lowestPrice => variants.isEmpty
      ? 0
      : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
}
