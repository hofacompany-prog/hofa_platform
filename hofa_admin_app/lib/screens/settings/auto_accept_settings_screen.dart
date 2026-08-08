import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/auto_accept_settings.dart';
import '../../providers/admin_providers.dart';

/// Tham số toàn sàn cho công tắc "Tự động nhận đơn" (branches.auto_accept_orders, store app) —
/// không cài riêng theo từng cửa hàng. Bật: cửa hàng có auto_accept_default_minutes (giới hạn
/// theo trần tính từ số món) để trượt xác nhận trước khi hệ thống tự nhận hộ. Tắt: cửa hàng có
/// manual_confirm_window_minutes để tự xác nhận, hết giờ đơn tự huỷ + chi nhánh tự đóng cửa.
class AutoAcceptSettingsScreen extends ConsumerStatefulWidget {
  const AutoAcceptSettingsScreen({super.key});

  @override
  ConsumerState<AutoAcceptSettingsScreen> createState() => _AutoAcceptSettingsScreenState();
}

class _AutoAcceptSettingsScreenState extends ConsumerState<AutoAcceptSettingsScreen> {
  final _defaultCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _incrementCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _manualWindowCtrl = TextEditingController();
  final _confirmSweepCtrl = TextEditingController();
  final _tierItemsCtrl = TextEditingController();
  final _tierValueCtrl = TextEditingController();
  final _prepDefaultBaseCtrl = TextEditingController();
  final _prepDefaultIncrementCtrl = TextEditingController();
  final _prepDefaultMaxCtrl = TextEditingController();
  final _prepCeilingBaseCtrl = TextEditingController();
  final _prepCeilingIncrementCtrl = TextEditingController();
  final _prepCeilingMaxCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _defaultCtrl.dispose();
    _baseCtrl.dispose();
    _incrementCtrl.dispose();
    _maxCtrl.dispose();
    _manualWindowCtrl.dispose();
    _confirmSweepCtrl.dispose();
    _tierItemsCtrl.dispose();
    _tierValueCtrl.dispose();
    _prepDefaultBaseCtrl.dispose();
    _prepDefaultIncrementCtrl.dispose();
    _prepDefaultMaxCtrl.dispose();
    _prepCeilingBaseCtrl.dispose();
    _prepCeilingIncrementCtrl.dispose();
    _prepCeilingMaxCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(AutoAcceptSettings s) {
    _defaultCtrl.text = s.autoAcceptDefaultMinutes.toString();
    _baseCtrl.text = s.autoAcceptPrepBaseMinutes.toString();
    _incrementCtrl.text = s.autoAcceptPrepIncrementMinutes.toString();
    _maxCtrl.text = s.autoAcceptPrepMaxMinutes.toString();
    _manualWindowCtrl.text = s.manualConfirmWindowMinutes.toString();
    _confirmSweepCtrl.text = s.confirmSweepSeconds.toString();
    _tierItemsCtrl.text = s.prepTierItems.toString();
    _tierValueCtrl.text = s.prepTierValueVnd.toString();
    _prepDefaultBaseCtrl.text = s.prepDefaultBaseMinutes.toString();
    _prepDefaultIncrementCtrl.text = s.prepDefaultIncrementMinutes.toString();
    _prepDefaultMaxCtrl.text = s.prepDefaultMaxMinutes.toString();
    _prepCeilingBaseCtrl.text = s.prepCeilingBaseMinutes.toString();
    _prepCeilingIncrementCtrl.text = s.prepCeilingIncrementMinutes.toString();
    _prepCeilingMaxCtrl.text = s.prepCeilingMaxMinutes.toString();
  }

  Future<void> _save(String? id) async {
    final defaultMin = int.tryParse(_defaultCtrl.text.trim());
    final base = int.tryParse(_baseCtrl.text.trim());
    final increment = int.tryParse(_incrementCtrl.text.trim());
    final max = int.tryParse(_maxCtrl.text.trim());
    final manualWindow = int.tryParse(_manualWindowCtrl.text.trim());
    final confirmSweep = int.tryParse(_confirmSweepCtrl.text.trim());
    if (defaultMin == null || defaultMin <= 0) {
      _showError('Thời gian mặc định không hợp lệ');
      return;
    }
    if (base == null || base <= 0) {
      _showError('Trần cho 1 món không hợp lệ');
      return;
    }
    if (increment == null || increment < 0) {
      _showError('Số phút cộng thêm mỗi món không hợp lệ');
      return;
    }
    if (max == null || max < base) {
      _showError('Trần tối đa toàn đơn phải lớn hơn hoặc bằng trần cho 1 món');
      return;
    }
    if (manualWindow == null || manualWindow <= 0) {
      _showError('Thời gian chờ xác nhận thủ công không hợp lệ');
      return;
    }
    if (confirmSweep == null || confirmSweep <= 0) {
      _showError('Thời gian thanh chạy màu không hợp lệ');
      return;
    }
    final tierItems = int.tryParse(_tierItemsCtrl.text.trim());
    final tierValue = int.tryParse(_tierValueCtrl.text.trim());
    final prepDefaultBase = int.tryParse(_prepDefaultBaseCtrl.text.trim());
    final prepDefaultIncrement = int.tryParse(_prepDefaultIncrementCtrl.text.trim());
    final prepDefaultMax = int.tryParse(_prepDefaultMaxCtrl.text.trim());
    final prepCeilingBase = int.tryParse(_prepCeilingBaseCtrl.text.trim());
    final prepCeilingIncrement = int.tryParse(_prepCeilingIncrementCtrl.text.trim());
    final prepCeilingMax = int.tryParse(_prepCeilingMaxCtrl.text.trim());
    if (tierItems == null || tierItems <= 0) {
      _showError('Mốc bậc theo số phần không hợp lệ');
      return;
    }
    if (tierValue == null || tierValue <= 0) {
      _showError('Mốc bậc theo giá trị đơn không hợp lệ');
      return;
    }
    if (prepDefaultBase == null || prepDefaultBase <= 0) {
      _showError('Thời gian chuẩn bị mặc định ở bậc 0 không hợp lệ');
      return;
    }
    if (prepDefaultIncrement == null || prepDefaultIncrement < 0) {
      _showError('Số phút cộng thêm mỗi bậc (mặc định) không hợp lệ');
      return;
    }
    if (prepDefaultMax == null || prepDefaultMax < prepDefaultBase) {
      _showError('Trần thời gian chuẩn bị mặc định phải lớn hơn hoặc bằng số phút ở bậc 0');
      return;
    }
    if (prepCeilingBase == null || prepCeilingBase < prepDefaultBase) {
      _showError('Số phút tối đa cửa hàng chỉnh được ở bậc 0 phải lớn hơn hoặc bằng thời gian mặc định ở bậc 0');
      return;
    }
    if (prepCeilingIncrement == null || prepCeilingIncrement < 0) {
      _showError('Số phút cộng thêm mỗi bậc (trần) không hợp lệ');
      return;
    }
    if (prepCeilingMax == null || prepCeilingMax < prepCeilingBase || prepCeilingMax < prepDefaultMax) {
      _showError('Trần tuyệt đối phải lớn hơn hoặc bằng cả trần ở bậc 0 lẫn trần thời gian chuẩn bị mặc định');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref.read(adminRepoProvider).updateAutoAcceptSettings(
            AutoAcceptSettings(
              id: id,
              autoAcceptDefaultMinutes: defaultMin,
              autoAcceptPrepBaseMinutes: base,
              autoAcceptPrepIncrementMinutes: increment,
              autoAcceptPrepMaxMinutes: max,
              manualConfirmWindowMinutes: manualWindow,
              confirmSweepSeconds: confirmSweep,
              prepTierItems: tierItems,
              prepTierValueVnd: tierValue,
              prepDefaultBaseMinutes: prepDefaultBase,
              prepDefaultIncrementMinutes: prepDefaultIncrement,
              prepDefaultMaxMinutes: prepDefaultMax,
              prepCeilingBaseMinutes: prepCeilingBase,
              prepCeilingIncrementMinutes: prepCeilingIncrement,
              prepCeilingMaxMinutes: prepCeilingMax,
            ),
          );
      ref.invalidate(autoAcceptSettingsProvider);
      if (mounted) {
        _fillFrom(saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông số')),
        );
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(autoAcceptSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Thông số')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (settings) {
          if (!_initialized) {
            _fillFrom(settings);
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Áp dụng cho toàn sàn — điều khiển hành vi công tắc "Tự động nhận đơn" ở '
                      'Cài đặt chi nhánh trong app cửa hàng, không cài riêng theo từng cửa hàng.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Khi bật "Tự động nhận đơn"',
                      child: Column(
                        children: [
                          _NumberField(
                            controller: _defaultCtrl,
                            label: 'Thời gian mặc định để tự nhận đơn (phút)',
                            helper: 'Số phút cửa hàng có để trượt xác nhận trước khi hệ thống tự nhận đơn hộ '
                                '(không vượt quá trần bên dưới).',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _baseCtrl,
                            label: 'Thời gian chuẩn bị tối đa cho 1 món (phút)',
                            helper: 'Trần thời gian chuẩn bị khi đơn chỉ có 1 món — cũng là giới hạn trên '
                                'của nút +/- ở màn nhận đơn.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _incrementCtrl,
                            label: 'Thời gian cộng thêm mỗi món tiếp theo (phút)',
                            helper: 'Từ món thứ 2 trở đi trong 1 đơn, mỗi món cộng thêm bấy nhiêu phút vào trần.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _maxCtrl,
                            label: 'Thời gian chuẩn bị tối đa toàn đơn (phút)',
                            helper: 'Trần tuyệt đối, bất kể đơn có bao nhiêu món.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Khi tắt "Tự động nhận đơn"',
                      child: _NumberField(
                        controller: _manualWindowCtrl,
                        label: 'Thời gian chờ xác nhận thủ công (phút)',
                        helper: 'Cửa hàng có bấy nhiêu phút để tự bấm xác nhận. Hết giờ, đơn tự huỷ và '
                            'chi nhánh tự chuyển sang "Tạm đóng cửa".',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Màn chi tiết đơn (mọi đơn mới)',
                      child: _NumberField(
                        controller: _confirmSweepCtrl,
                        label: 'Thời gian thanh chạy màu để xác nhận thời gian chuẩn bị (giây)',
                        helper: 'Ở màn chi tiết đơn của cửa hàng, dải màu chạy trên thanh trượt xác nhận '
                            'trong bấy nhiêu giây. Hết giờ mà chưa trượt, hệ thống tự chốt số phút đang '
                            'hiện trên bộ đếm +/- làm thời gian chuẩn bị và tự xác nhận đơn. Áp dụng cho '
                            'mọi đơn mới, không phụ thuộc công tắc "Tự động nhận đơn" ở trên.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Mốc bậc thời gian chuẩn bị (dùng chung)',
                      child: Column(
                        children: [
                          Text(
                            'Đơn nào chạm mốc SỐ PHẦN hay GIÁ TRỊ trước thì tính theo bậc đó (lấy bậc lớn '
                            'hơn trong 2 cách tính). Dùng chung cho cả thời gian chuẩn bị mặc định lẫn trần '
                            '+/- bên dưới.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _tierItemsCtrl,
                            label: 'Cứ mỗi bao nhiêu phần thì +1 bậc (số phần)',
                            helper: 'Số phần = tổng số lượng món trong đơn (không phân biệt loại món).',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _tierValueCtrl,
                            label: 'Cứ mỗi bao nhiêu đồng thì +1 bậc (giá trị đơn)',
                            helper: 'Tính theo tổng tiền món (subtotal), chưa gồm phí ship.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Thời gian chuẩn bị mặc định (theo bậc)',
                      child: Column(
                        children: [
                          Text(
                            'Số phút hiện sẵn ở màn chi tiết đơn (store app) khi đơn vừa vào — chốt luôn lúc '
                            'tạo đơn, không đổi dù sau đó bạn có sửa lại Thông số.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultBaseCtrl,
                            label: 'Thời gian chuẩn bị mặc định ở bậc 0 (phút)',
                            helper: 'Áp dụng cho đơn chưa chạm mốc bậc nào ở trên.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultIncrementCtrl,
                            label: 'Cộng thêm mỗi bậc (phút)',
                            helper: 'Mỗi bậc vượt qua, cộng thêm bấy nhiêu phút vào thời gian chuẩn bị mặc định.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepDefaultMaxCtrl,
                            label: 'Trần thời gian chuẩn bị mặc định (phút)',
                            helper: 'Trần tuyệt đối, bất kể bậc cao đến đâu.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Thời gian tối đa cửa hàng được chỉnh (theo bậc)',
                      child: Column(
                        children: [
                          Text(
                            'Giới hạn trên của nút +/- ở màn chi tiết đơn — cửa hàng không bấm + vượt quá '
                            'số này, dù đang ở trạng thái mặc định hay đã tự chỉnh.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingBaseCtrl,
                            label: 'Trần +/- ở bậc 0 (phút)',
                            helper: 'Phải lớn hơn hoặc bằng thời gian chuẩn bị mặc định ở bậc 0.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingIncrementCtrl,
                            label: 'Cộng thêm mỗi bậc (phút)',
                            helper: 'Mỗi bậc vượt qua, cộng thêm bấy nhiêu phút vào trần +/-.',
                          ),
                          const SizedBox(height: 12),
                          _NumberField(
                            controller: _prepCeilingMaxCtrl,
                            label: 'Trần +/- tuyệt đối (phút)',
                            helper: 'Trần tuyệt đối, bất kể bậc cao đến đâu.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(settings.id),
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String helper;
  const _NumberField({required this.controller, required this.label, required this.helper});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, border: const OutlineInputBorder()),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
