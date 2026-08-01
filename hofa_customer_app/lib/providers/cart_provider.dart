import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';

const _cartStorageKey = 'hofa_cart_v1';

/// Giỏ hàng chỉ chứa món của 1 cửa hàng/1 chi nhánh tại 1 thời điểm — khớp với
/// POST /orders (mỗi đơn thuộc đúng 1 merchant_id + branch_id).
class CartState {
  final String? merchantId;
  final String? merchantName;
  final String? branchId;
  final String salesModel; // 'instant' | 'scheduled' — theo sản phẩm đầu tiên bỏ vào giỏ
  final List<CartItem> items;

  const CartState({
    this.merchantId,
    this.merchantName,
    this.branchId,
    this.salesModel = 'instant',
    this.items = const [],
  });

  int get subtotal => items.fold(0, (sum, i) => sum + i.lineTotal);
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);
  bool get isEmpty => items.isEmpty;

  Map<String, dynamic> toJson() => {
        'merchant_id': merchantId,
        'merchant_name': merchantName,
        'branch_id': branchId,
        'sales_model': salesModel,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory CartState.fromJson(Map<String, dynamic> json) => CartState(
        merchantId: json['merchant_id'] as String?,
        merchantName: json['merchant_name'] as String?,
        branchId: json['branch_id'] as String?,
        salesModel: json['sales_model'] as String? ?? 'instant',
        items: (json['items'] as List? ?? []).map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartStorageKey);
    if (raw == null) return;
    try {
      state = CartState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // dữ liệu cũ hỏng định dạng — bỏ qua, coi như giỏ trống
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cartStorageKey, jsonEncode(state.toJson()));
  }

  /// Giỏ trống hoặc đang chứa món của đúng cửa hàng này thì thêm được luôn.
  bool belongsToCurrentCart(String merchantId) => state.isEmpty || state.merchantId == merchantId;

  Future<void> addItem({
    required String merchantId,
    required String merchantName,
    required String branchId,
    required String salesModel,
    required CartItem item,
  }) async {
    final items = List<CartItem>.from(state.items);
    final idx = items.indexWhere((e) => e.variantId == item.variantId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(quantity: items[idx].quantity + item.quantity);
    } else {
      items.add(item);
    }
    state = CartState(
      merchantId: merchantId,
      merchantName: merchantName,
      branchId: branchId,
      salesModel: salesModel,
      items: items,
    );
    await _persist();
  }

  Future<void> updateQuantity(String variantId, int quantity) async {
    if (quantity <= 0) {
      await removeItem(variantId);
      return;
    }
    final items = state.items.map((e) => e.variantId == variantId ? e.copyWith(quantity: quantity) : e).toList();
    state = CartState(
      merchantId: state.merchantId,
      merchantName: state.merchantName,
      branchId: state.branchId,
      salesModel: state.salesModel,
      items: items,
    );
    await _persist();
  }

  Future<void> removeItem(String variantId) async {
    final items = state.items.where((e) => e.variantId != variantId).toList();
    state = items.isEmpty
        ? const CartState()
        : CartState(
            merchantId: state.merchantId,
            merchantName: state.merchantName,
            branchId: state.branchId,
            salesModel: state.salesModel,
            items: items,
          );
    await _persist();
  }

  Future<void> clear() async {
    state = const CartState();
    await _persist();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier());
