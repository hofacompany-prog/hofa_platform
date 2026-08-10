import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../models/branch.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../location/location_picker_screen.dart';

/// Sửa địa chỉ + bán kính giao hàng của 1 chi nhánh.
class BranchEditScreen extends ConsumerStatefulWidget {
  final Branch branch;
  const BranchEditScreen({super.key, required this.branch});

  @override
  ConsumerState<BranchEditScreen> createState() => _BranchEditScreenState();
}

class _BranchEditScreenState extends ConsumerState<BranchEditScreen> {
  final _repo = MerchantRepository();

  late final _nameCtrl = TextEditingController(text: widget.branch.name);
  late final _phoneCtrl = TextEditingController(
    text: widget.branch.phone ?? '',
  );
  late final _line1Ctrl = TextEditingController(text: widget.branch.line1);
  late final _wardCtrl = TextEditingController(text: widget.branch.ward ?? '');
  late final _districtCtrl = TextEditingController(
    text: widget.branch.district ?? '',
  );
  late final _provinceCtrl = TextEditingController(
    text: widget.branch.province,
  );
  late final _radiusCtrl = TextEditingController(
    text: widget.branch.deliveryRadiusKm.toString(),
  );

  late double _lat = widget.branch.latitude;
  late double _lng = widget.branch.longitude;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _line1Ctrl.dispose();
    _wardCtrl.dispose();
    _districtCtrl.dispose();
    _provinceCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  /// Chọn lại vị trí trên bản đồ — giống màn chọn địa chỉ giao hàng bên app khách và màn
  /// tạo cửa hàng — điền lại luôn địa chỉ chữ, chủ cửa hàng vẫn sửa tay được sau đó.
  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (picked == null) return;
    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
      if (picked.line1.isNotEmpty) _line1Ctrl.text = picked.line1;
      if (picked.ward != null && picked.ward!.isNotEmpty) {
        _wardCtrl.text = picked.ward!;
      }
      if (picked.district != null && picked.district!.isNotEmpty) {
        _districtCtrl.text = picked.district!;
      }
      if (picked.province.isNotEmpty) _provinceCtrl.text = picked.province;
    });
  }

  Future<void> _save() async {
    final radiusKm = num.tryParse(_radiusCtrl.text.trim());
    if (radiusKm == null || radiusKm <= 0 || radiusKm > 100) {
      setState(
        () => _error = 'Bán kính giao hàng phải lớn hơn 0 và tối đa 100km',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.updateBranch(widget.branch.id, {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'line1': _line1Ctrl.text.trim(),
        'ward': _wardCtrl.text.trim().isEmpty ? null : _wardCtrl.text.trim(),
        'district': _districtCtrl.text.trim().isEmpty
            ? null
            : _districtCtrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        'delivery_radius_km': radiusKm,
      });
      ref.invalidate(myMerchantProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sửa chi nhánh')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên chi nhánh',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickLocation,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Chọn vị trí trên bản đồ'),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Vị trí hiện tại: (${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _line1Ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ (số nhà, đường)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wardCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phường/Xã',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _districtCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quận/Huyện',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _provinceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tỉnh/Thành phố',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _radiusCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bán kính giao hàng (km)',
                    helperText:
                        'Khách ngoài bán kính này (và ngoài mức mặc định toàn sàn) sẽ không thấy cửa hàng',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Lưu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
