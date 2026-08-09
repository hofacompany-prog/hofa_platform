import 'cart_item.dart';

/// Dữ liệu tạm cho luồng "Mua ngay" ở trang chi tiết sản phẩm — gửi thẳng qua GoRouter
/// `extra` tới CheckoutScreen, KHÔNG đi qua giỏ hàng chung (cartProvider), để chỉ tính
/// tiền/đặt đơn cho đúng 1 sản phẩm này và giữ nguyên giỏ hàng hiện có của khách.
class BuyNowRequest {
  final String merchantId;
  final String merchantName;
  final String branchId;
  final String salesModel;
  final CartItem item;

  const BuyNowRequest({
    required this.merchantId,
    required this.merchantName,
    required this.branchId,
    required this.salesModel,
    required this.item,
  });
}
