import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../providers/app_providers.dart';
import '../providers/cart_provider.dart';
import 'topping_picker_dialog.dart';

/// Thêm nhanh 1 sản phẩm vào giỏ từ danh sách sản phẩm (dấu "+" trên ProductCard) — cùng luồng
/// với nút thêm vào giỏ ở trang chi tiết sản phẩm (hỏi Giá sỉ/Đặt trước nếu sản phẩm bán sỉ,
/// cảnh báo nếu giỏ đang có món của cửa hàng/hình thức khác) nhưng luôn dùng biến thể mặc
/// định, không cần mở trang chi tiết. Luôn mở popup topping trước khi thêm (kể cả sản phẩm
/// không có topping) để khách chỉnh số lượng ngay trong popup đó.
Future<void> quickAddToCart(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  final variant = product.defaultVariant;
  if (variant == null) return;

  final toppingGroups = await ref.read(
    toppingGroupsProvider(product.id).future,
  );
  if (!context.mounted) return;
  final result = await showToppingPickerDialog(context, groups: toppingGroups);
  if (result == null) return; // huỷ popup thì không thêm vào giỏ
  final toppings = result.toppings;
  final note = result.note;
  final quantity = result.quantity;

  String? orderKind;
  if (product.isWholesale) {
    if (!context.mounted) return;
    orderKind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Thêm vào'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'wholesale'),
            child: const Text('Giá sỉ'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'preorder'),
            child: const Text('Đặt trước'),
          ),
        ],
      ),
    );
    if (orderKind == null) return;
  }

  if (!context.mounted) return;
  final cartNotifier = ref.read(cartProvider.notifier);
  final cartState = ref.read(cartProvider);
  if (!cartNotifier.belongsToCurrentCart(
    product.merchantId,
    product.salesModel,
  )) {
    final differentMerchant = cartState.merchantId != product.merchantId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          differentMerchant
              ? 'Giỏ hàng có món của cửa hàng khác'
              : 'Giỏ hàng có món khác hình thức bán',
        ),
        content: Text(
          differentMerchant
              ? 'Giỏ hàng hiện đang có món từ "${cartState.merchantName}". Mỗi đơn chỉ đặt được 1 cửa hàng — xoá giỏ hiện tại để thêm món mới?'
              : 'Giỏ hàng hiện đang có món ${cartState.salesModel == 'scheduled' ? 'đặt trước/bán sỉ' : 'giao ngay'}, khác với sản phẩm này. Giao ngay và đặt trước/bán sỉ đặt riêng — xoá giỏ hiện tại để thêm món mới?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá giỏ cũ'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await cartNotifier.clear();
  }

  if (!context.mounted) return;
  try {
    final branches = await ref.read(
      merchantBranchesProvider(product.merchantId).future,
    );
    if (branches.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cửa hàng chưa có chi nhánh nhận đơn')),
        );
      }
      return;
    }
    final branch = branches.firstWhere(
      (b) => b.isMain,
      orElse: () => branches.first,
    );
    final merchant = await ref.read(
      merchantDetailProvider(product.merchantId).future,
    );

    await cartNotifier.addItem(
      merchantId: product.merchantId,
      merchantName: merchant.name,
      branchId: branch.id,
      salesModel: product.salesModel,
      item: CartItem(
        lineId: '${variant.id}_${DateTime.now().microsecondsSinceEpoch}',
        productId: product.id,
        productName: product.name,
        productImage: product.images.isNotEmpty ? product.images.first : null,
        variantId: variant.id,
        variantName: variant.name,
        unitPrice: variant.price,
        basePrice: variant.price,
        quantity: quantity,
        unit: product.unit,
        toppings: toppings,
        note: note,
        orderKind: orderKind,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orderKind == 'wholesale'
                ? 'Đã thêm vào Giá sỉ'
                : orderKind == 'preorder'
                ? 'Đã thêm vào Đặt trước'
                : 'Đã thêm vào Giỏ hàng',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }
}
