import 'package:flutter/material.dart';

/// Bộ icon dựng sẵn cho danh mục — key lưu vào cột categories.icon_name, IconData chỉ
/// tồn tại ở client (không lưu được vào DB) nên cả admin lẫn customer app đều phải khai
/// báo đúng bộ này. Sửa/thêm icon thì sửa đồng thời ở admin app (lib/core/category_icons.dart).
const categoryIcons = <String, IconData>{
  'food': Icons.restaurant,
  'fastfood': Icons.fastfood,
  'drink': Icons.local_cafe,
  'fresh': Icons.eco,
  'meat_seafood': Icons.set_meal,
  'bakery': Icons.cake,
  'grocery': Icons.local_grocery_store,
  'electronics': Icons.devices,
  'phone': Icons.smartphone,
  'appliance': Icons.kitchen,
  'hardware': Icons.hardware,
  'fashion': Icons.checkroom,
  'beauty': Icons.spa,
  'health': Icons.medical_services,
  'mom_baby': Icons.child_care,
  'pet': Icons.pets,
  'book_office': Icons.menu_book,
  'toy': Icons.toys,
  'sport': Icons.sports_soccer,
  'vehicle': Icons.two_wheeler,
  'home': Icons.home_outlined,
  'construction': Icons.construction,
  'agriculture': Icons.agriculture,
  'other': Icons.category_outlined,
};

const categoryIconLabels = <String, String>{
  'food': 'Đồ ăn',
  'fastfood': 'Ăn nhanh',
  'drink': 'Đồ uống',
  'fresh': 'Đồ tươi sống',
  'meat_seafood': 'Thịt cá',
  'bakery': 'Bánh kẹo',
  'grocery': 'Tạp hoá',
  'electronics': 'Điện máy',
  'phone': 'Điện thoại',
  'appliance': 'Gia dụng',
  'hardware': 'Dụng cụ cơ khí',
  'fashion': 'Thời trang',
  'beauty': 'Làm đẹp',
  'health': 'Sức khoẻ',
  'mom_baby': 'Mẹ và bé',
  'pet': 'Thú cưng',
  'book_office': 'Sách - VPP',
  'toy': 'Đồ chơi',
  'sport': 'Thể thao',
  'vehicle': 'Xe cộ',
  'home': 'Nhà cửa',
  'construction': 'Vật liệu XD',
  'agriculture': 'Nông nghiệp',
  'other': 'Khác',
};

IconData categoryIconOf(String? name) => categoryIcons[name] ?? Icons.category_outlined;
