import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../models/bank.dart';
import '../../models/merchant.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_repository.dart';
import '../../widgets/image_upload_field.dart';
import '../../widgets/multi_image_upload_field.dart';

/// Hồ sơ đầy đủ của cửa hàng — mọi thông tin cửa hàng cần cung cấp cho HOFA
/// (mô tả, ảnh, giấy tờ pháp lý, tài khoản nhận tiền, điều kiện vận hành).
class StoreProfileEditScreen extends ConsumerStatefulWidget {
  final Merchant merchant;
  const StoreProfileEditScreen({super.key, required this.merchant});

  @override
  ConsumerState<StoreProfileEditScreen> createState() =>
      _StoreProfileEditScreenState();
}

class _StoreProfileEditScreenState
    extends ConsumerState<StoreProfileEditScreen> {
  final _repo = MerchantRepository();

  late final _descCtrl = TextEditingController(
    text: widget.merchant.description ?? '',
  );
  late final _emailCtrl = TextEditingController(
    text: widget.merchant.email ?? '',
  );
  late final _minOrderCtrl = TextEditingController(
    text: widget.merchant.minOrderAmount.toString(),
  );
  late final _prepCtrl = TextEditingController(
    text: widget.merchant.avgPrepMinutes.toString(),
  );
  late final _bankAccNoCtrl = TextEditingController(
    text: widget.merchant.bankAccountNo ?? '',
  );
  late final _bankAccNameCtrl = TextEditingController(
    text: widget.merchant.bankAccountName ?? '',
  );
  // Chỉ để XEM, không cho gõ tay — luôn khớp đúng ngân hàng đang chọn ở dropdown.
  late final _bankBinCtrl = TextEditingController(
    text: widget.merchant.bankBin ?? '',
  );
  late final _taxCodeCtrl = TextEditingController(
    text: widget.merchant.taxCode ?? '',
  );
  late final _licenseCtrl = TextEditingController(
    text: widget.merchant.businessLicenseNo ?? '',
  );

  late String? _logoUrl = widget.merchant.logoUrl;
  late String? _coverUrl = widget.merchant.coverUrl;
  late List<String> _legalDocUrls = List.of(widget.merchant.legalDocUrls);
  late List<String> _photoUrls = List.of(widget.merchant.photoUrls);
  late final Set<String> _classificationIds = widget.merchant.classifications
      .map((c) => c.id)
      .toSet();

  Bank? _selectedBank;
  bool _bankPrefillAttempted = false;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    _emailCtrl.dispose();
    _minOrderCtrl.dispose();
    _prepCtrl.dispose();
    _bankAccNoCtrl.dispose();
    _bankAccNameCtrl.dispose();
    _bankBinCtrl.dispose();
    _taxCodeCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Có số tài khoản mà chưa chọn đúng ngân hàng trong dropdown (vd tên ngân hàng gõ tay
    // trước đây không khớp tên nào trong danh sách banks) — chặn lưu để tránh lưu nhầm
    // bank_bin=null, hoặc lưu nhầm sang ngân hàng khác khiến QR chuyển khoản bị ngân hàng
    // từ chối lúc admin duyệt rút tiền.
    if (_bankAccNoCtrl.text.trim().isNotEmpty && _selectedBank == null) {
      setState(
        () => _error =
            'Đã nhập số tài khoản nhưng chưa chọn đúng ngân hàng ở trên',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.updateMerchant(widget.merchant.id, {
        'description': _descCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        if (_logoUrl != null) 'logo_url': _logoUrl,
        if (_coverUrl != null) 'cover_url': _coverUrl,
        'legal_doc_urls': _legalDocUrls,
        'photo_urls': _photoUrls,
        'min_order_amount':
            int.tryParse(_minOrderCtrl.text.trim()) ??
            widget.merchant.minOrderAmount,
        'avg_prep_minutes':
            int.tryParse(_prepCtrl.text.trim()) ??
            widget.merchant.avgPrepMinutes,
        'bank_name': _selectedBank?.name,
        'bank_bin': _selectedBank?.bin,
        'bank_account_no': _bankAccNoCtrl.text.trim().isEmpty
            ? null
            : _bankAccNoCtrl.text.trim(),
        'bank_account_name': _bankAccNameCtrl.text.trim().isEmpty
            ? null
            : _bankAccNameCtrl.text.trim(),
        'tax_code': _taxCodeCtrl.text.trim().isEmpty
            ? null
            : _taxCodeCtrl.text.trim(),
        'business_license_no': _licenseCtrl.text.trim().isEmpty
            ? null
            : _licenseCtrl.text.trim(),
      });
      await _repo.setMerchantClassifications(
        widget.merchant.id,
        _classificationIds.toList(),
      );
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
    final banksAsync = ref.watch(banksProvider);
    // Khớp ngân hàng đã lưu (bank_bin) với danh sách vừa tải để chọn sẵn trong dropdown — chỉ
    // thử 1 lần lúc danh sách vừa có dữ liệu (mirror register_driver_screen.dart), rơi về
    // khớp theo tên nếu cửa hàng chưa từng có bin (trước hofa-db/66_merchant_bank_bin.sql).
    if (!_bankPrefillAttempted) {
      final banks = banksAsync.valueOrNull;
      if (banks != null) {
        _bankPrefillAttempted = true;
        final bin = widget.merchant.bankBin;
        final matches = banks.where(
          (b) => bin != null && bin.isNotEmpty
              ? b.bin == bin
              : b.name == widget.merchant.bankName,
        );
        if (matches.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedBank = matches.first;
                _bankBinCtrl.text = matches.first.bin;
              });
            }
          });
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sửa hồ sơ cửa hàng')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ảnh cửa hàng',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ImageUploadField(
                      label: 'Ảnh đại diện (logo)',
                      folder: 'merchants',
                      initialUrl: _logoUrl,
                      onChanged: (url) => _logoUrl = url,
                    ),
                    const SizedBox(width: 16),
                    ImageUploadField(
                      label: 'Ảnh bìa',
                      folder: 'merchants',
                      initialUrl: _coverUrl,
                      onChanged: (url) => _coverUrl = url,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                MultiImageUploadField(
                  label: 'Ảnh khác của cửa hàng (không bắt buộc)',
                  folder: 'merchants',
                  initialUrls: _photoUrls,
                  onChanged: (urls) => _photoUrls = urls,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả cửa hàng',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'Phân loại cửa hàng',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final itemsAsync = ref.watch(
                      merchantClassificationsProvider,
                    );
                    return itemsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (e, _) =>
                          Text('Không tải được danh sách phân loại: $e'),
                      data: (items) {
                        if (items.isEmpty) {
                          return const Text('Chưa có phân loại nào.');
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: items.map((c) {
                            final selected = _classificationIds.contains(c.id);
                            return FilterChip(
                              label: Text(c.name),
                              selected: selected,
                              onSelected: (v) => setState(() {
                                v
                                    ? _classificationIds.add(c.id)
                                    : _classificationIds.remove(c.id);
                              }),
                            );
                          }).toList(),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email liên hệ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minOrderCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Đơn tối thiểu (VNĐ)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _prepCtrl,
                        decoration: const InputDecoration(
                          labelText: 'TG chuẩn bị (phút)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  'Giấy tờ pháp lý',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _taxCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mã số thuế',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _licenseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số giấy phép kinh doanh',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                MultiImageUploadField(
                  label: 'Ảnh giấy phép kinh doanh / giấy tờ pháp lý',
                  folder: 'merchants',
                  initialUrls: _legalDocUrls,
                  onChanged: (urls) => _legalDocUrls = urls,
                ),
                const Divider(height: 32),
                Text(
                  'Tài khoản nhận tiền',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                banksAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) =>
                      Text('Không tải được danh sách ngân hàng: $e'),
                  data: (banks) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Bank>(
                          initialValue: _selectedBank,
                          decoration: const InputDecoration(
                            labelText: 'Ngân hàng',
                            border: OutlineInputBorder(),
                          ),
                          items: banks
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedBank = v;
                            _bankBinCtrl.text = v?.bin ?? '';
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _bankBinCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Mã BIN',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số tài khoản',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên chủ tài khoản',
                    border: OutlineInputBorder(),
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
