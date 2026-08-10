import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/favorites_provider.dart';

/// Nút tim bấm để thêm/bớt 1 cửa hàng khỏi "Cửa hàng yêu thích" — dùng chung cho MerchantCard
/// (thẻ danh sách) và merchant_detail_screen.dart (AppBar). [background] true vẽ thêm nền
/// tròn trắng mờ phía sau tim, hợp khi đặt đè lên ảnh (thẻ cửa hàng); false dùng trần cho
/// AppBar (đã có nền sẵn từ theme).
class MerchantFavoriteButton extends ConsumerWidget {
  final String merchantId;
  final bool background;
  final double size;
  const MerchantFavoriteButton({
    super.key,
    required this.merchantId,
    this.background = false,
    this.size = 22,
  });

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(favoriteIdsProvider.notifier).toggle(merchantId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsAsync = ref.watch(favoriteIdsProvider);
    final isFavorite = idsAsync.valueOrNull?.contains(merchantId) ?? false;
    final icon = Icon(
      isFavorite ? Icons.favorite : Icons.favorite_border,
      color: isFavorite ? Colors.red : (background ? Colors.black87 : null),
      size: size,
    );

    final button = IconButton(
      tooltip: isFavorite ? 'Bỏ yêu thích' : 'Thêm vào yêu thích',
      onPressed: () => _toggle(context, ref),
      visualDensity: VisualDensity.compact,
      icon: icon,
    );

    if (!background) return button;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: button,
    );
  }
}
