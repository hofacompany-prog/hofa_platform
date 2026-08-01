import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/cloudinary_uploader.dart';

/// Ô chọn + upload 1 ảnh lên Cloudinary, dùng chung cho logo cửa hàng và ảnh sản phẩm.
/// [onChanged] được gọi với URL Cloudinary ngay sau khi upload xong.
class ImageUploadField extends StatefulWidget {
  final String label;
  final String folder; // 'merchants' | 'products' — khớp ALLOWED_FOLDERS ở server
  final String? initialUrl;
  final ValueChanged<String> onChanged;

  const ImageUploadField({
    super.key,
    required this.label,
    required this.folder,
    this.initialUrl,
    required this.onChanged,
  });

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  String? _url;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

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
      setState(() => _url = url);
      widget.onChanged(url);
    } catch (e) {
      setState(() => _error = 'Tải ảnh lỗi: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: _uploading ? null : _pick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : (_url != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          _url!,
                          fit: BoxFit.cover,
                          width: 140,
                          height: 140,
                          errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: theme.colorScheme.outline, size: 28),
                            const SizedBox(height: 4),
                            Text('Chọn ảnh', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      )),
          ),
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
