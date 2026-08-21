import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/require_login.dart';
import '../models/address.dart';
import '../providers/app_providers.dart';
import '../providers/auth_providers.dart';
import '../screens/address/address_picker_screen.dart';

/// Luồng thêm địa chỉ kiểu Grab/ShopeeFood: chọn vị trí trên BẢN ĐỒ TRƯỚC (AddressPickerScreen
/// tự định vị GPS hiện tại lúc mở), sau đó mới điền tên/SĐT người nhận + mô tả địa điểm giao —
/// ngược thứ tự so với form cũ (điền địa chỉ tay trước, bản đồ chỉ để tham khảo). Dùng chung
/// cho: thanh "Giao ngay" ở trang chủ, nút "Thêm địa chỉ" (màn Hồ sơ), nút "Thêm địa chỉ mới"
/// và luồng "Đặt hàng" khi chưa có địa chỉ nào (checkout_screen.dart).
///
/// Trả về [Address] vừa tạo, hoặc null nếu khách huỷ/chưa đăng nhập ở bất kỳ bước nào.
/// [setAsDefault] mặc định true — đặt luôn địa chỉ vừa thêm làm mặc định (server tự gỡ mặc
/// định của địa chỉ cũ, xem PATCH/POST /addresses ở users.js).
Future<Address?> addAddressViaMap(
  BuildContext context,
  WidgetRef ref, {
  bool setAsDefault = true,
}) async {
  if (!await requireLogin(context)) return null;
  if (!context.mounted) return null;

  final picked = await Navigator.of(
    context,
  ).push<PickedAddress>(MaterialPageRoute(builder: (_) => const AddressPickerScreen()));
  if (picked == null || !context.mounted) return null;

  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? requiredValidator(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Bắt buộc nhập' : null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Thông tin người nhận'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            picked.line1,
                            picked.ward,
                            picked.district,
                            picked.province,
                          ].where((e) => e != null && e.isNotEmpty).join(', '),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên người nhận',
                  ),
                  validator: requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SĐT người nhận',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: requiredValidator,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả địa điểm giao (không bắt buộc)',
                    hintText: 'VD: nhà màu vàng, cổng sau, gọi trước khi tới...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, true);
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  if (ok != true) return null;

  final created = await ref.read(userRepoProvider).createAddress({
    'recipient_name': nameCtrl.text.trim(),
    'recipient_phone': phoneCtrl.text.trim(),
    'line1': picked.line1,
    if (picked.ward != null) 'ward': picked.ward,
    if (picked.district != null) 'district': picked.district,
    'province': picked.province,
    'latitude': picked.latitude,
    'longitude': picked.longitude,
    if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
    if (setAsDefault) 'is_default': true,
  });
  ref.invalidate(addressesProvider);
  return created;
}
