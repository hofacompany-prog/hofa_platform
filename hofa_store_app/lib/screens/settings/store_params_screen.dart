import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../models/merchant.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';

/// Các con số điều khiển hành vi công tắc "Tự động nhận đơn" (branch_settings_screen.dart) —
/// áp dụng cho mọi chi nhánh của cửa hàng. Mỗi trường có chú thích rõ ý nghĩa ngay bên dưới.
class StoreParamsScreen extends ConsumerStatefulWidget {
  final Merchant merchant;
  const StoreParamsScreen({super.key, required this.merchant});

  @override
  ConsumerState<StoreParamsScreen> createState() => _StoreParamsScreenState();
}

class _StoreParamsScreenState extends ConsumerState<StoreParamsScreen> {
  final _repo = MerchantRepository();

  late final _defaultCtrl = TextEditingController(text: widget.merchant.autoAcceptDefaultMinutes.toString());
  late final _baseCtrl = TextEditingController(text: widget.merchant.autoAcceptPrepBaseMinutes.toString());
  late final _incrementCtrl = TextEditingController(text: widget.merchant.autoAcceptPrepIncrementMinutes.toString());
  late final _maxCtrl = TextEditingController(text: widget.merchant.autoAcceptPrepMaxMinutes.toString());
  late final _manualWindowCtrl = TextEditingController(text: widget.merchant.manualConfirmWindowMinutes.toString());

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _defaultCtrl.dispose();
    _baseCtrl.dispose();
    _incrementCtrl.dispose();
    _maxCtrl.dispose();
    _manualWindowCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.updateMerchant(widget.merchant.id, {
        'auto_accept_default_minutes': int.tryParse(_defaultCtrl.text.trim()) ?? widget.merchant.autoAcceptDefaultMinutes,
        'auto_accept_prep_base_minutes': int.tryParse(_baseCtrl.text.trim()) ?? widget.merchant.autoAcceptPrepBaseMinutes,
        'auto_accept_prep_increment_minutes':
            int.tryParse(_incrementCtrl.text.trim()) ?? widget.merchant.autoAcceptPrepIncrementMinutes,
        'auto_accept_prep_max_minutes': int.tryParse(_maxCtrl.text.trim()) ?? widget.merchant.autoAcceptPrepMaxMinutes,
        'manual_confirm_window_minutes':
            int.tryParse(_manualWindowCtrl.text.trim()) ?? widget.merchant.manualConfirmWindowMinutes,
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

  Widget _field(String label, String helper, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 4),
          Text(helper, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông số')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Khi bật "Tự động nhận đơn"', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _field(
                  'Thời gian mặc định để tự nhận đơn (phút)',
                  'Số phút cửa hàng có để trượt xác nhận trước khi hệ thống tự nhận đơn hộ (không vượt quá trần bên dưới).',
                  _defaultCtrl,
                ),
                _field(
                  'Thời gian chuẩn bị tối đa cho 1 món (phút)',
                  'Trần thời gian chuẩn bị khi đơn chỉ có 1 món — cũng là giới hạn trên của nút +/- ở màn nhận đơn.',
                  _baseCtrl,
                ),
                _field(
                  'Thời gian cộng thêm mỗi món tiếp theo (phút)',
                  'Từ món thứ 2 trở đi trong 1 đơn, mỗi món cộng thêm bấy nhiêu phút vào trần.',
                  _incrementCtrl,
                ),
                _field(
                  'Thời gian chuẩn bị tối đa toàn đơn (phút)',
                  'Trần tuyệt đối, bất kể đơn có bao nhiêu món.',
                  _maxCtrl,
                ),
                const Divider(height: 8),
                Text('Khi tắt "Tự động nhận đơn"', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _field(
                  'Thời gian chờ xác nhận thủ công (phút)',
                  'Cửa hàng có bấy nhiêu phút để tự bấm xác nhận. Hết giờ, đơn tự huỷ và chi nhánh tự chuyển sang "Tạm đóng cửa".',
                  _manualWindowCtrl,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 8),
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
