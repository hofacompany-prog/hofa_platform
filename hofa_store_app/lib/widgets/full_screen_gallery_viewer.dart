import 'package:flutter/material.dart';

/// Xem 1 danh sách ảnh full màn hình — vuốt trái/phải xem ảnh kế tiếp (PageView), phóng to
/// bằng 2 ngón (InteractiveViewer). Mở qua [open], không cần đăng ký route go_router riêng.
class FullScreenGalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  static void open(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullScreenGalleryViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<FullScreenGalleryViewer> createState() =>
      _FullScreenGalleryViewerState();
}

class _FullScreenGalleryViewerState extends State<FullScreenGalleryViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.images.length > 1
            ? Text('${_index + 1}/${widget.images.length}')
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.images[i],
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
