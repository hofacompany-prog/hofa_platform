import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Nút back dùng ở AppBar của các tab điều hướng chính (Sản phẩm, Đơn hàng, Kho hàng, Danh
/// mục, Cài đặt) — các màn này không tự có nút back mặc định vì được điều hướng bằng
/// context.go (thay vị trí hiện tại, không đẩy thêm vào ngăn xếp). canPop() phòng trường hợp
/// có vào từ 1 chỗ khác bằng push thật, còn lại quay thẳng về Trang chủ.
class NavBackButton extends StatelessWidget {
  const NavBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
    );
  }
}
