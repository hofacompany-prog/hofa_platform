import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../models/merchant.dart';
import '../../models/bank.dart';
import '../../models/branch_hours.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/full_screen_gallery_viewer.dart';
import '../../widgets/image_upload_field.dart';
import '../../widgets/multi_image_upload_field.dart';
import '../../widgets/merchant_classification_picker.dart';
import 'merchant_devices_card.dart';
import 'merchant_fee_tiers_card.dart';
import 'merchant_topping_groups_card.dart';
import 'merchants_screen.dart' show merchantStatusLabels;
import '../../core/responsive.dart';

const merchantTypeLabels = {
  'standard': 'HOFA Standard',
  'regular': 'Cửa hàng thường',
  'wholesale': 'Cửa hàng bán sỉ',
  'buy_on_behalf': 'Mua hộ',
};

class MerchantDetailScreen extends ConsumerStatefulWidget {
  final String merchantId;
  const MerchantDetailScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantDetailScreen> createState() =>
      _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends ConsumerState<MerchantDetailScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    bool goBackAfter = false,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(merchantDetailProvider(widget.merchantId));
      ref.invalidate(merchantsProvider);
      ref.invalidate(statsProvider);
      if (goBackAfter && mounted) context.go('/merchants');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editInfo(Merchant m) async {
    final nameCtrl = TextEditingController(text: m.name);
    final descCtrl = TextEditingController(text: m.description ?? '');
    final phoneCtrl = TextEditingController(text: m.phone ?? '');
    final emailCtrl = TextEditingController(text: m.email ?? '');
    final commissionCtrl = TextEditingController(
      text: m.commissionRate.toString(),
    );
    final vatRateCtrl = TextEditingController(text: m.vatRate.toString());
    final pitRateCtrl = TextEditingController(text: m.pitRate.toString());
    final minOrderCtrl = TextEditingController(
      text: m.minOrderAmount.toString(),
    );
    final prepCtrl = TextEditingController(text: m.avgPrepMinutes.toString());
    final bankAccNoCtrl = TextEditingController(text: m.bankAccountNo ?? '');
    final bankAccNameCtrl = TextEditingController(
      text: m.bankAccountName ?? '',
    );
    final taxCodeCtrl = TextEditingController(text: m.taxCode ?? '');
    final licenseCtrl = TextEditingController(text: m.businessLicenseNo ?? '');
    var merchantType = m.merchantType;
    var classificationIds = m.classifications.map((c) => c.id).toSet();
    var logoUrl = m.logoUrl;
    var coverUrl = m.coverUrl;
    var legalDocUrls = List.of(m.legalDocUrls);
    var photoUrls = List.of(m.photoUrls);

    // Danh sách ngân hàng cho dropdown — nạp trước lúc mở dialog (banksProvider hiếm khi đổi,
    // không cần watch() re-render trong dialog). Khớp lại theo bin (ổn định hơn tên nếu tên
    // ngân hàng trong danh mục từng đổi), rơi về tên nếu cửa hàng chưa từng có bin (trước
    // migration 66).
    List<Bank> banks = [];
    try {
      banks = await ref.read(banksProvider.future);
    } catch (_) {}
    Bank? selectedBank;
    for (final b in banks) {
      if ((m.bankBin != null && b.bin == m.bankBin) ||
          (m.bankBin == null && b.name == m.bankName)) {
        selectedBank = b;
        break;
      }
    }
    // Chỉ để XEM, không cho gõ tay — luôn khớp đúng ngân hàng đang chọn ở dropdown, tránh
    // trường hợp admin tự sửa sai lệch giữa tên và mã BIN thật.
    final bankBinCtrl = TextEditingController(text: selectedBank?.bin ?? '');
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa thông tin cửa hàng'),
          content: SizedBox(
            width: dialogWidth(context, 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ImageUploadField(
                        label: 'Ảnh đại diện',
                        folder: 'merchants',
                        initialUrl: logoUrl,
                        onChanged: (url) => logoUrl = url,
                      ),
                      const SizedBox(width: 16),
                      ImageUploadField(
                        label: 'Ảnh bìa',
                        folder: 'merchants',
                        initialUrl: coverUrl,
                        onChanged: (url) => coverUrl = url,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MultiImageUploadField(
                    label: 'Ảnh khác của cửa hàng',
                    folder: 'merchants',
                    initialUrls: photoUrls,
                    onChanged: (urls) => photoUrls = urls,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên cửa hàng',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Mô tả'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: merchantType,
                    decoration: const InputDecoration(
                      labelText: 'Loại cửa hàng',
                    ),
                    items: merchantTypeLabels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setInner(() => merchantType = v ?? merchantType),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Phân loại cửa hàng',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MerchantClassificationPicker(
                    selectedIds: classificationIds,
                    onChanged: (next) =>
                        setInner(() => classificationIds = next),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commissionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Hoa hồng (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: prepCtrl,
                          decoration: const InputDecoration(
                            labelText: 'TG chuẩn bị (phút)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minOrderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đơn tối thiểu (VNĐ)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: vatRateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Thuế GTGT (%)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: pitRateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Thuế TNCN (%)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Dùng cho màn Tài chính ở app cửa hàng — mặc định theo hộ kinh doanh dịch vụ ăn uống (TT40/2021/TT-BTC).',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ),
                  const Divider(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ngân hàng & pháp lý',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Bank>(
                          initialValue: selectedBank,
                          decoration: const InputDecoration(
                            labelText: 'Ngân hàng',
                          ),
                          items: banks
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setInner(() {
                            selectedBank = v;
                            bankBinCtrl.text = v?.bin ?? '';
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: bankBinCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Mã BIN',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankAccNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankAccNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên chủ tài khoản',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: taxCodeCtrl,
                    decoration: const InputDecoration(labelText: 'Mã số thuế'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: licenseCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số giấy phép KD',
                    ),
                  ),
                  const SizedBox(height: 16),
                  MultiImageUploadField(
                    label: 'Ảnh giấy phép kinh doanh / giấy tờ pháp lý',
                    folder: 'merchants',
                    initialUrls: legalDocUrls,
                    onChanged: (urls) => legalDocUrls = urls,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    // Chỉ chặn lưu nếu admin THỰC SỰ vừa đổi số tài khoản mà chưa chọn đúng ngân hàng trong
    // dropdown — không chặn nếu số tài khoản giữ nguyên như cũ (dữ liệu cũ nhập tay trước khi
    // có tính năng mã BIN, tên ngân hàng không khớp danh sách banks hiện tại), nếu không mọi
    // lần Lưu (kể cả chỉ đổi phân loại/mô tả, không đụng gì tới ngân hàng) đều bị chặn oan.
    final bankAccNoChanged =
        bankAccNoCtrl.text.trim() != (m.bankAccountNo ?? '').trim();
    if (bankAccNoChanged &&
        bankAccNoCtrl.text.trim().isNotEmpty &&
        selectedBank == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã nhập số tài khoản nhưng chưa chọn đúng ngân hàng trong danh sách — mở lại và chọn ngân hàng trước khi lưu',
            ),
          ),
        );
      }
      return;
    }

    await _run(() async {
      await ref.read(adminRepoProvider).updateMerchant(m.id, {
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'merchant_type': merchantType,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (coverUrl != null) 'cover_url': coverUrl,
        'legal_doc_urls': legalDocUrls,
        'photo_urls': photoUrls,
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        'commission_rate':
            num.tryParse(commissionCtrl.text.trim()) ?? m.commissionRate,
        'vat_rate': num.tryParse(vatRateCtrl.text.trim()) ?? m.vatRate,
        'pit_rate': num.tryParse(pitRateCtrl.text.trim()) ?? m.pitRate,
        'min_order_amount':
            int.tryParse(minOrderCtrl.text.trim()) ?? m.minOrderAmount,
        'avg_prep_minutes':
            int.tryParse(prepCtrl.text.trim()) ?? m.avgPrepMinutes,
        'bank_name': selectedBank?.name,
        'bank_bin': selectedBank?.bin,
        'bank_account_no': bankAccNoCtrl.text.trim().isEmpty
            ? null
            : bankAccNoCtrl.text.trim(),
        'bank_account_name': bankAccNameCtrl.text.trim().isEmpty
            ? null
            : bankAccNameCtrl.text.trim(),
        'tax_code': taxCodeCtrl.text.trim().isEmpty
            ? null
            : taxCodeCtrl.text.trim(),
        'business_license_no': licenseCtrl.text.trim().isEmpty
            ? null
            : licenseCtrl.text.trim(),
      });
      await ref
          .read(adminRepoProvider)
          .setMerchantClassifications(m.id, classificationIds.toList());
    });
  }

  Future<void> _editBranch(Branch b) async {
    final nameCtrl = TextEditingController(text: b.name);
    final phoneCtrl = TextEditingController(text: b.phone ?? '');
    final line1Ctrl = TextEditingController(text: b.line1);
    final wardCtrl = TextEditingController(text: b.ward ?? '');
    final districtCtrl = TextEditingController(text: b.district ?? '');
    final provinceCtrl = TextEditingController(text: b.province);
    final latCtrl = TextEditingController(text: b.latitude.toString());
    final lngCtrl = TextEditingController(text: b.longitude.toString());
    final radiusCtrl = TextEditingController(
      text: b.deliveryRadiusKm.toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sửa chi nhánh — ${b.name}'),
        content: SizedBox(
          width: dialogWidth(context, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên chi nhánh'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: line1Ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ (số nhà, đường)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: wardCtrl,
                  decoration: const InputDecoration(labelText: 'Phường/Xã'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: districtCtrl,
                  decoration: const InputDecoration(labelText: 'Quận/Huyện'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: provinceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tỉnh/Thành phố',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(labelText: 'Vĩ độ'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(labelText: 'Kinh độ'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: radiusCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bán kính giao hàng (km)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final radiusKm = num.tryParse(radiusCtrl.text.trim());
    if (radiusKm == null || radiusKm <= 0 || radiusKm > 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bán kính giao hàng phải lớn hơn 0 và tối đa 100km'),
          ),
        );
      }
      return;
    }

    await _run(
      () => ref.read(adminRepoProvider).updateBranch(b.id, {
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        'line1': line1Ctrl.text.trim(),
        'ward': wardCtrl.text.trim().isEmpty ? null : wardCtrl.text.trim(),
        'district': districtCtrl.text.trim().isEmpty
            ? null
            : districtCtrl.text.trim(),
        'province': provinceCtrl.text.trim(),
        'latitude': double.tryParse(latCtrl.text.trim()) ?? b.latitude,
        'longitude': double.tryParse(lngCtrl.text.trim()) ?? b.longitude,
        'delivery_radius_km': radiusKm,
      }),
    );
  }

  TimeOfDay? _parseHourTime(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtHourTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Sửa giờ mở cửa từng ngày trong tuần cho 1 chi nhánh — cùng luồng dữ liệu
  /// (GET/PUT /branches/:id/hours) và cách gõ (công tắc bật/tắt + chọn giờ mở/đóng riêng từng
  /// ngày) với màn hình Cửa hàng tự sửa (hofa_store_app/lib/screens/settings/branch_hours_screen.dart),
  /// chỉ khác ở chỗ admin dùng dialog thay vì màn hình riêng cho gọn.
  Future<void> _viewBranchHours(Branch b) async {
    List<BranchHour>? existing;
    String? loadError;
    try {
      existing = await ref.read(adminRepoProvider).branchHours(b.id);
    } catch (e) {
      loadError = '$e';
    }
    if (!mounted) return;
    if (loadError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $loadError')));
      return;
    }

    final enabled = List<bool>.filled(7, false);
    final openTimes = List<TimeOfDay>.filled(
      7,
      const TimeOfDay(hour: 8, minute: 0),
    );
    final closeTimes = List<TimeOfDay>.filled(
      7,
      const TimeOfDay(hour: 21, minute: 0),
    );
    for (final h in existing!) {
      final o = _parseHourTime(h.openTime);
      final c = _parseHourTime(h.closeTime);
      if (o == null || c == null) continue;
      enabled[h.weekday] = true;
      openTimes[h.weekday] = o;
      closeTimes[h.weekday] = c;
    }

    var saving = false;
    String? saveError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setInner) {
          Future<void> pickTime(int i, {required bool isOpen}) async {
            final picked = await showTimePicker(
              context: dialogContext,
              initialTime: isOpen ? openTimes[i] : closeTimes[i],
            );
            if (picked == null) return;
            setInner(() {
              if (isOpen) {
                openTimes[i] = picked;
              } else {
                closeTimes[i] = picked;
              }
            });
          }

          return AlertDialog(
            title: Text('Giờ mở cửa — ${b.name}'),
            content: SizedBox(
              width: dialogWidth(context, 380),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Row(
                        children: [
                          SizedBox(width: 88, child: Text(weekdayLabels[i]!)),
                          Switch(
                            value: enabled[i],
                            onChanged: (v) => setInner(() => enabled[i] = v),
                          ),
                          if (enabled[i]) ...[
                            Expanded(
                              child: TextButton(
                                onPressed: () => pickTime(i, isOpen: true),
                                child: Text(_fmtHourTime(openTimes[i])),
                              ),
                            ),
                            const Text('—'),
                            Expanded(
                              child: TextButton(
                                onPressed: () => pickTime(i, isOpen: false),
                                child: Text(_fmtHourTime(closeTimes[i])),
                              ),
                            ),
                          ] else
                            const Expanded(
                              child: Text(
                                'Đóng cửa',
                                style: TextStyle(color: Colors.black45),
                              ),
                            ),
                        ],
                      ),
                    if (saveError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Lỗi: $saveError',
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Đóng'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setInner(() {
                          saving = true;
                          saveError = null;
                        });
                        try {
                          final hours = <BranchHour>[
                            for (var i = 0; i < 7; i++)
                              if (enabled[i])
                                BranchHour(
                                  weekday: i,
                                  openTime: _fmtHourTime(openTimes[i]),
                                  closeTime: _fmtHourTime(closeTimes[i]),
                                ),
                          ];
                          await ref
                              .read(adminRepoProvider)
                              .setBranchHours(b.id, hours);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (e) {
                          setInner(() {
                            saveError = '$e';
                            saving = false;
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeStatus(Merchant m) async {
    var selected = m.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text('Đổi trạng thái — ${m.name}'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setInner(() => selected = v ?? selected),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: merchantStatusLabels.entries
                  .map(
                    (e) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: e.key,
                      title: Text(e.value),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selected == m.status) return;
    await _run(
      () => ref
          .read(adminRepoProvider)
          .setMerchantStatus(m.id, selected)
          .then((_) {}),
    );
  }

  Future<void> _review(Merchant m, bool approve) async {
    var certify = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(approve ? 'Duyệt cửa hàng?' : 'Từ chối cửa hàng?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approve
                    ? '"${m.name}" sẽ được mở bán và hiện với khách hàng.'
                    : '"${m.name}" sẽ bị từ chối.',
              ),
              if (approve) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: certify,
                  onChanged: (v) => setInner(() => certify = v ?? false),
                  title: const Text('Cấp nhãn HOFA Standard'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              style: approve
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(approve ? 'Duyệt' : 'Từ chối'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref
          .read(adminRepoProvider)
          .reviewMerchant(m.id, approve: approve, certifyStandard: certify)
          .then((_) {}),
    );
  }

  Future<void> _deleteMerchant(Merchant m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá vĩnh viễn cửa hàng?'),
        content: Text(
          'Xoá triệt để "${m.name}" — không thể khôi phục. Mất luôn TOÀN BỘ chi nhánh, sản '
          'phẩm, đơn hàng, giao dịch thanh toán, đánh giá, và sổ kho của cửa hàng này (không '
          'còn chỉ là ẩn/đóng cửa hàng như trước). Dùng "Tạm dừng" nếu chỉ muốn ngừng nhận '
          'đơn mà vẫn giữ lại lịch sử.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(adminRepoProvider).deleteMerchant(m.id),
      goBackAfter: true,
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(merchantDetailProvider(widget.merchantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/merchants'),
        ),
        title: const Text('Chi tiết cửa hàng'),
        actions: [
          detailAsync.maybeWhen(
            data: (m) => IconButton(
              tooltip: 'Xoá cửa hàng',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteMerchant(m),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (m) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  backgroundImage: m.logoUrl != null
                                      ? NetworkImage(m.logoUrl!)
                                      : null,
                                  child: m.logoUrl == null
                                      ? Icon(
                                          Icons.storefront,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                if (m.photoUrls.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _MerchantPhotoStrip(photoUrls: m.photoUrls),
                                ],
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              m.name,
                                              style:
                                                  theme.textTheme.headlineSmall,
                                            ),
                                          ),
                                          if (m.isStandard)
                                            Icon(
                                              Icons.verified,
                                              color: theme.colorScheme.primary,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          Chip(
                                            label: Text(
                                              merchantStatusLabels[m.status] ??
                                                  m.status,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          if (m.isBuyOnBehalf)
                                            Chip(
                                              avatar: Icon(
                                                Icons.shopping_bag_outlined,
                                                size: 16,
                                                color:
                                                    theme.colorScheme.secondary,
                                              ),
                                              label: const Text('Mua hộ'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor: theme
                                                  .colorScheme
                                                  .secondary
                                                  .withValues(alpha: 0.12),
                                              labelStyle: TextStyle(
                                                color:
                                                    theme.colorScheme.secondary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (m.coverUrl != null) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  m.coverUrl!,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                            const Divider(height: 32),
                            _row('Slug', m.slug),
                            _row('Mô tả', m.description ?? '—'),
                            _row(
                              'Loại cửa hàng',
                              merchantTypeLabels[m.merchantType] ??
                                  m.merchantType,
                            ),
                            _row(
                              'Phân loại cửa hàng',
                              m.classifications.isEmpty
                                  ? '—'
                                  : m.classifications
                                        .map((c) => c.name)
                                        .join(', '),
                            ),
                            _row('SĐT', m.phone ?? '—'),
                            _row('Email', m.email ?? '—'),
                            _row('Hoa hồng', '${m.commissionRate}%'),
                            _row('Đơn tối thiểu', formatVnd(m.minOrderAmount)),
                            _row('TG chuẩn bị', '${m.avgPrepMinutes} phút'),
                            _row(
                              'Đánh giá',
                              '${m.ratingAvg}★ (${m.ratingCount})',
                            ),
                            if (m.createdAt != null)
                              _row('Tạo lúc', formatDateTime(m.createdAt!)),
                            const Divider(height: 24),
                            Text(
                              'Ngân hàng & pháp lý',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            _row('Ngân hàng', m.bankName ?? '—'),
                            _row('Số tài khoản', m.bankAccountNo ?? '—'),
                            _row('Chủ tài khoản', m.bankAccountName ?? '—'),
                            _row('Mã số thuế', m.taxCode ?? '—'),
                            _row('Giấy phép KD', m.businessLicenseNo ?? '—'),
                            if (m.legalDocUrls.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: m.legalDocUrls
                                    .map(
                                      (url) => ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          url,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _editInfo(m),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Sửa thông tin'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeStatus(m),
                                  icon: const Icon(Icons.sync_alt),
                                  label: const Text('Đổi trạng thái'),
                                ),
                                if (m.status == 'pending_review') ...[
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(m, true),
                                    child: const Text('Duyệt'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(m, false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: theme.colorScheme.error,
                                    ),
                                    child: const Text('Từ chối'),
                                  ),
                                ] else if (m.status == 'active')
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => ref
                                                .read(adminRepoProvider)
                                                .setMerchantPaused(m.id, true)
                                                .then((_) {}),
                                          ),
                                    child: const Text('Tạm dừng'),
                                  )
                                else if (m.status == 'paused')
                                  FilledButton.tonal(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => ref
                                                .read(adminRepoProvider)
                                                .setMerchantPaused(m.id, false)
                                                .then((_) {}),
                                          ),
                                    child: const Text('Mở lại'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (m.owner != null)
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chủ cửa hàng',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              _row('Họ tên', m.owner!.fullName),
                              _row('SĐT', m.owner!.phone),
                              _row('Email', m.owner!.email ?? '—'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chi nhánh (${m.branches?.length ?? 0})',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if ((m.branches ?? []).isEmpty)
                              const Text('Chưa có chi nhánh nào'),
                            ...(m.branches ?? []).map(
                              (b) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.storefront_outlined,
                                          size: 18,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${b.name}${b.isMain ? ' (chính)' : ''}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                b.fullLine,
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                              Text(
                                                'Bán kính giao: ${b.deliveryRadiusKm} km',
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            b.isOpen ? 'Đang mở' : 'Đang đóng',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: b.isOpen
                                              ? theme.colorScheme.primary
                                                    .withValues(alpha: 0.12)
                                              : theme
                                                    .colorScheme
                                                    .errorContainer,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 26),
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _editBranch(b),
                                            icon: const Icon(
                                              Icons.edit_location_alt_outlined,
                                              size: 16,
                                            ),
                                            label: const Text('Sửa'),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _viewBranchHours(b),
                                            icon: const Icon(
                                              Icons.schedule_outlined,
                                              size: 16,
                                            ),
                                            label: const Text('Giờ mở cửa'),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (m.isBuyOnBehalf) ...[
                      const SizedBox(height: 16),
                      MerchantFeeTiersCard(merchant: m),
                    ],
                    const SizedBox(height: 16),
                    MerchantToppingGroupsCard(merchant: m),
                    const SizedBox(height: 16),
                    MerchantDevicesCard(merchant: m),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dải ảnh nhỏ cạnh logo cửa hàng — tối đa 3 ảnh, ảnh cuối đè số "+N" nếu còn ảnh chưa hiện.
/// Bấm ảnh nào mở xem full màn hình bắt đầu đúng ảnh đó, vuốt được sang các ảnh còn lại.
class _MerchantPhotoStrip extends StatelessWidget {
  final List<String> photoUrls;
  const _MerchantPhotoStrip({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    final shown = photoUrls.take(1).toList();
    final hasMore = photoUrls.length > shown.length;
    return SizedBox(
      width: 56,
      height: 56,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < shown.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => FullScreenGalleryViewer.open(
                context,
                images: photoUrls,
                initialIndex: i,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  shown[i],
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // Còn ảnh chưa hiện — bấm mới xem hết, không hiện đè lên ảnh như trước.
          if (hasMore)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => FullScreenGalleryViewer.open(
                context,
                images: photoUrls,
                initialIndex: 0,
              ),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Icon(Icons.more_horiz, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
