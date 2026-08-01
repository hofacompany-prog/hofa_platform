import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../models/branch.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';

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
  late final _phoneCtrl = TextEditingController(text: widget.branch.phone ?? '');
  late final _line1Ctrl = TextEditingController(text: widget.branch.line1);
  late final _wardCtrl = TextEditingController(text: widget.branch.ward ?? '');
  late final _districtCtrl = TextEditingController(text: widget.branch.district ?? '');
  late final _provinceCtrl = TextEditingController(text: widget.branch.province);
  late final _latCtrl = TextEditingController(text: widget.branch.latitude.toString());
  late final _lngCtrl = TextEditingController(text: widget.branch.longitude.toString());
  late final _radiusCtrl = TextEditingController(text: widget.branch.deliveryRadiusKm.toString());

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
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
        'district': _districtCtrl.text.trim().isEmpty ? null : _districtCtrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'latitude': double.tryParse(_latCtrl.text.trim()) ?? widget.branch.latitude,
        'longitude': double.tryParse(_lngCtrl.text.trim()) ?? widget.branch.longitude,
        'delivery_radius_km': num.tryParse(_radiusCtrl.text.trim()) ?? widget.branch.deliveryRadiusKm,
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
                  decoration: const InputDecoration(labelText: 'Tên chi nhánh', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _line1Ctrl,
                  decoration: const InputDecoration(labelText: 'Địa chỉ (số nhà, đường)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wardCtrl,
                  decoration: const InputDecoration(labelText: 'Phường/Xã', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _districtCtrl,
                  decoration: const InputDecoration(labelText: 'Quận/Huyện', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _provinceCtrl,
                  decoration: const InputDecoration(labelText: 'Tỉnh/Thành phố', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latCtrl,
                        decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lngCtrl,
                        decoration: const InputDecoration(labelText: 'Kinh độ (longitude)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _radiusCtrl,
                  decoration: const InputDecoration(labelText: 'Bán kính giao hàng (km)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
