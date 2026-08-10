import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/cloudinary_uploader.dart';
import 'full_screen_gallery_viewer.dart';

/// Ô chọn + upload NHIỀU ảnh lên Cloudinary (vd giấy tờ pháp lý). [onChanged] được gọi
/// với danh sách URL đầy đủ mỗi khi thêm/xoá 1 ảnh.
class MultiImageUploadField extends StatefulWidget {
  final String label;
  final String folder;
  final List<String> initialUrls;
  final ValueChanged<List<String>> onChanged;

  const MultiImageUploadField({
    super.key,
    required this.label,
    required this.folder,
    this.initialUrls = const [],
    required this.onChanged,
  });

  @override
  State<MultiImageUploadField> createState() => _MultiImageUploadFieldState();
}

class _MultiImageUploadFieldState extends State<MultiImageUploadField> {
  late List<String> _urls = List.of(widget.initialUrls);
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final url = await CloudinaryUploader().uploadImage(bytes, file.name, folder: widget.folder);
      setState(() => _urls = [..._urls, url]);
      widget.onChanged(_urls);
    } catch (e) {
      setState(() => _error = 'Tải ảnh lỗi: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _remove(String url) {
    setState(() => _urls = _urls.where((u) => u != url).toList());
    widget.onChanged(_urls);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final url in _urls)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => FullScreenGalleryViewer.open(
                        context,
                        images: _urls,
                        initialIndex: _urls.indexOf(url),
                      ),
                      child: Image.network(url, width: 100, height: 100, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: () => _remove(url),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            InkWell(
              onTap: _uploading ? null : _pick,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: _uploading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: Icon(Icons.add_photo_alternate_outlined, color: theme.colorScheme.outline, size: 26),
                      ),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ),
      ],
    );
  }
}
