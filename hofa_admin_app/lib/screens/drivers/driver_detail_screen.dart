import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../models/bank.dart';
import '../../models/driver.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/image_upload_field.dart';
import '../../widgets/multi_image_upload_field.dart';

const _vehicleTypeOptions = [
  ('xe máy', 'Xe máy'),
  ('xe tải 500kg', 'Xe tải nhỏ (≤500kg)'),
  ('xe tải 1000kg', 'Xe tải (≤1 tấn)'),
];

const _rejectionReasonPresets = [
  'Giấy tờ mờ/không rõ',
  'Thông tin không khớp giấy tờ',
  'Thiếu ảnh giấy tờ',
  'Thông tin ngân hàng không hợp lệ',
  'Khác',
];

/// Chi tiết đầy đủ 1 tài xế — xem + sửa MỌI thông tin (cá nhân, giấy tờ, xe, ngân hàng, ảnh) ở
/// 1 màn duy nhất thay vì các dialog rời rạc ở drivers_screen.dart, cộng thêm xoá tài xế + xem
/// dữ liệu chặn xoá. Thông tin cá nhân (họ tên/SĐT/email/ảnh đại diện) nằm ở bảng users, sửa qua
/// updateUser; phần chuyên môn tài xế (CCCD/GPLX/xe/ngân hàng/ảnh giấy tờ/auto_accept) nằm ở
/// bảng drivers, sửa qua updateDriver — xem PATCH /admin/users/:id vs /admin/drivers/:id.
class DriverDetailScreen extends ConsumerStatefulWidget {
  final String driverId;
  const DriverDetailScreen({super.key, required this.driverId});

  @override
  ConsumerState<DriverDetailScreen> createState() =>
      _DriverDetailScreenState();
}

class _DriverDetailScreenState extends ConsumerState<DriverDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(driverDetailProvider(widget.driverId));
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editBasicInfo(Driver d) async {
    final nameCtrl = TextEditingController(text: d.fullName ?? '');
    final phoneCtrl = TextEditingController(text: d.phone ?? '');
    final emailCtrl = TextEditingController(text: d.email ?? '');
    var avatarUrl = d.avatarUrl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa thông tin cơ bản'),
          content: SizedBox(
            width: dialogWidth(context, 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ImageUploadField(
                      label: 'Ảnh đại diện',
                      folder: 'drivers',
                      initialUrl: avatarUrl,
                      onChanged: (url) => avatarUrl = url,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Họ tên'),
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

    await _run(
      () => ref.read(adminRepoProvider).updateUser(d.userId, {
        'full_name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }),
    );
  }

  /// Sửa hồ sơ chuyên môn: CCCD, GPLX (+ hạn), xe (+ tải trọng), ngân hàng — không đụng
  /// verified_at/rejected_at.
  Future<void> _editProfile(Driver d) async {
    List<Bank> banks;
    try {
      banks = await ref.read(banksProvider.future);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được danh sách ngân hàng: $e')),
        );
      }
      return;
    }
    if (!mounted) return;

    final nationalIdCtrl = TextEditingController(text: d.nationalId ?? '');
    final licenseNoCtrl = TextEditingController(text: d.licenseNo ?? '');
    final plateCtrl = TextEditingController(text: d.vehiclePlate ?? '');
    final capacityCtrl = TextEditingController(
      text: d.vehicleCapacityKg?.toString() ?? '',
    );
    final accountNumberCtrl = TextEditingController(
      text: d.bankAccountNumber ?? '',
    );
    final accountHolderCtrl = TextEditingController(
      text: d.bankAccountHolder ?? '',
    );
    var vehicleType = d.vehicleType ?? _vehicleTypeOptions.first.$1;
    var licenseExpiry = d.licenseExpiry;
    Bank? selectedBank;
    if (d.bankBin != null) {
      final match = banks.where((b) => b.bin == d.bankBin);
      if (match.isNotEmpty) selectedBank = match.first;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Sửa hồ sơ tài xế'),
          content: SizedBox(
            width: dialogWidth(context, 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nationalIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số CCCD/CMND',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: licenseNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số GPLX',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          licenseExpiry == null
                              ? 'Hạn GPLX: chưa có'
                              : 'Hạn GPLX: ${formatDateTime(licenseExpiry!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: licenseExpiry ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setInner(() => licenseExpiry = picked);
                          }
                        },
                        child: const Text('Chọn ngày'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: vehicleType,
                    decoration: const InputDecoration(
                      labelText: 'Loại xe',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _vehicleTypeOptions
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v.$1, child: Text(v.$2)),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setInner(() => vehicleType = v ?? vehicleType),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: plateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Biển số xe',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: capacityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tải trọng (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const Divider(height: 28),
                  Text(
                    'Tài khoản nhận tiền',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Bank>(
                    initialValue: selectedBank,
                    decoration: const InputDecoration(
                      labelText: 'Ngân hàng',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: banks
                        .map(
                          (b) =>
                              DropdownMenuItem(value: b, child: Text(b.name)),
                        )
                        .toList(),
                    onChanged: (v) => setInner(() => selectedBank = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accountNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accountHolderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên chủ tài khoản',
                      border: OutlineInputBorder(),
                      isDense: true,
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
      ),
    );
    if (ok != true) return;

    await _run(
      () => ref.read(adminRepoProvider).updateDriver(d.id, {
        'national_id': nationalIdCtrl.text.trim(),
        'license_no': licenseNoCtrl.text.trim(),
        if (licenseExpiry != null)
          'license_expiry': licenseExpiry!.toIso8601String().substring(0, 10),
        'vehicle_type': vehicleType,
        'vehicle_plate': plateCtrl.text.trim(),
        if (capacityCtrl.text.trim().isNotEmpty)
          'vehicle_capacity_kg': num.tryParse(capacityCtrl.text.trim()),
        if (selectedBank != null) 'bank_name': selectedBank!.name,
        if (selectedBank != null) 'bank_bin': selectedBank!.bin,
        'bank_account_number': accountNumberCtrl.text.trim(),
        'bank_account_holder': accountHolderCtrl.text.trim(),
      }),
    );
  }

  Future<void> _editDocuments(Driver d) async {
    var urls = List<String>.of(d.documentUrls);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa ảnh giấy tờ'),
        content: SizedBox(
          width: dialogWidth(context, 480),
          child: SingleChildScrollView(
            child: MultiImageUploadField(
              label: 'Ảnh CCCD/GPLX/giấy tờ xe',
              folder: 'drivers',
              initialUrls: urls,
              onChanged: (v) => urls = v,
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

    await _run(
      () => ref
          .read(adminRepoProvider)
          .updateDriver(d.id, {'document_urls': urls}),
    );
  }

  Future<void> _verify(Driver d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duyệt hồ sơ tài xế?'),
        content: Text(
          'Xác nhận giấy tờ của tài xế này là hợp lệ.\n\n'
          'CMND/CCCD: ${d.nationalId ?? "—"}\n'
          'Bằng lái: ${d.licenseNo ?? "—"}\n'
          'Xe: ${d.vehicleType ?? "—"} · ${d.vehiclePlate ?? "—"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Duyệt'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(adminRepoProvider).verifyDriver(d.id));
  }

  Future<void> _reject(Driver d) async {
    var reason = _rejectionReasonPresets.first;
    final customCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Từ chối hồ sơ tài xế?'),
          content: SizedBox(
            width: dialogWidth(context, 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tài xế sẽ nhận được thông báo kèm lý do, sửa/nộp lại hồ sơ để được xét duyệt tiếp.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(
                    labelText: 'Lý do',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _rejectionReasonPresets
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setInner(() => reason = v ?? reason),
                ),
                if (reason == 'Khác') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Ghi rõ lý do',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Từ chối'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final finalReason = reason == 'Khác' ? customCtrl.text.trim() : reason;
    if (finalReason.isEmpty) return;
    await _run(() => ref.read(adminRepoProvider).rejectDriver(d.id, finalReason));
  }

  /// Gỡ tài xế kẹt ở 1 trạng thái (thường 'busy') không tự nhận được chuyến mới.
  Future<void> _changeStatus(Driver d) async {
    var selected = d.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Đổi trạng thái tài xế'),
          content: SizedBox(
            width: dialogWidth(context, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dùng khi tài xế bị kẹt trạng thái (vd "Đang giao" mãi) và không nhận được chuyến mới.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: driverStatusLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setInner(() => selected = v ?? selected),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(adminRepoProvider).forceDriverStatus(d.id, selected),
    );
  }

  Future<void> _toggleAutoAccept(Driver d) async {
    await _run(
      () => ref
          .read(adminRepoProvider)
          .updateDriver(d.id, {'auto_accept': !d.autoAccept}),
    );
  }

  Future<void> _deleteDriver(Driver d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá hồ sơ tài xế?'),
        content: Text(
          'Xoá hồ sơ tài xế của "${d.fullName ?? d.phone ?? d.id}" — tài khoản đăng nhập vẫn '
          'còn (chỉ mất phần hồ sơ chuyên môn tài xế: giấy tờ, xe, ví). Nếu còn chuyến giao chưa '
          'xong hoặc còn giữ tiền ví thì sẽ bị chặn kèm lý do cụ thể.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).deleteDriver(d.id);
      ref.invalidate(driversProvider);
      if (mounted) context.go('/drivers');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailAsync = ref.watch(driverDetailProvider(widget.driverId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/drivers'),
        ),
        title: const Text('Chi tiết tài xế'),
        actions: [
          detailAsync.maybeWhen(
            data: (d) => IconButton(
              tooltip: 'Xoá tài xế',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _deleteDriver(d),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (d) {
          final verification = driverVerificationState(d);
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
                                  backgroundImage: d.avatarUrl != null
                                      ? NetworkImage(d.avatarUrl!)
                                      : null,
                                  child: d.avatarUrl == null
                                      ? Icon(
                                          Icons.person,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.fullName?.isNotEmpty == true
                                            ? d.fullName!
                                            : (d.phone ?? d.id),
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Chip(
                                            label: Text(
                                              switch (verification) {
                                                DriverVerificationState
                                                  .verified =>
                                                  'Đã duyệt',
                                                DriverVerificationState
                                                  .rejected =>
                                                  'Bị từ chối',
                                                DriverVerificationState
                                                  .pending =>
                                                  'Chờ duyệt',
                                              },
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor: switch (verification) {
                                              DriverVerificationState
                                                .verified =>
                                                Colors.green.withValues(
                                                  alpha: 0.15,
                                                ),
                                              DriverVerificationState
                                                .rejected =>
                                                theme
                                                    .colorScheme
                                                    .errorContainer,
                                              DriverVerificationState
                                                .pending =>
                                                Colors.orange.withValues(
                                                  alpha: 0.15,
                                                ),
                                            },
                                          ),
                                          ActionChip(
                                            label: Text(
                                              driverStatusLabels[d.status] ??
                                                  d.status,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _busy
                                                ? null
                                                : () => _changeStatus(d),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            _row('Số điện thoại', d.phone ?? '—'),
                            _row('Email', d.email ?? '—'),
                            _row(
                              'Tạo lúc',
                              d.createdAt != null
                                  ? formatDateTime(d.createdAt!)
                                  : '—',
                            ),
                            if (verification ==
                                DriverVerificationState.rejected)
                              _row(
                                'Lý do từ chối',
                                d.rejectionReason ?? '—',
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _editBasicInfo(d),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Sửa thông tin cơ bản'),
                                ),
                                if (verification !=
                                    DriverVerificationState.verified) ...[
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.error,
                                    ),
                                    onPressed: _busy ? null : () => _reject(d),
                                    child: const Text('Từ chối'),
                                  ),
                                  FilledButton(
                                    onPressed: _busy ? null : () => _verify(d),
                                    child: const Text('Duyệt hồ sơ'),
                                  ),
                                ],
                              ],
                            ),
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Hồ sơ & giấy tờ',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _editProfile(d),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Sửa'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _row('Số CCCD/CMND', d.nationalId ?? '—'),
                            _row('Số GPLX', d.licenseNo ?? '—'),
                            _row(
                              'Hạn GPLX',
                              d.licenseExpiry != null
                                  ? formatDateTime(d.licenseExpiry!)
                                  : '—',
                            ),
                            _row('Loại xe', d.vehicleType ?? '—'),
                            _row('Biển số xe', d.vehiclePlate ?? '—'),
                            _row(
                              'Tải trọng',
                              d.vehicleCapacityKg != null
                                  ? '${d.vehicleCapacityKg} kg'
                                  : '—',
                            ),
                            const Divider(height: 24),
                            Text(
                              'Tài khoản nhận tiền',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 4),
                            _row('Ngân hàng', d.bankName ?? '—'),
                            _row('Số tài khoản', d.bankAccountNumber ?? '—'),
                            _row('Chủ tài khoản', d.bankAccountHolder ?? '—'),
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Ảnh giấy tờ (${d.documentUrls.length})',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _editDocuments(d),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Sửa'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (d.documentUrls.isEmpty)
                              const Text('Chưa có ảnh giấy tờ nào')
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: d.documentUrls
                                    .map(
                                      (url) => ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          8,
                                        ),
                                        child: Image.network(
                                          url,
                                          width: 90,
                                          height: 90,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
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
                              'Làm việc & ví',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Tự động nhận đơn'),
                              subtitle: const Text(
                                'Bật thì hệ thống tự gán đơn cho tài xế này, không cần tự bấm nhận',
                              ),
                              value: d.autoAccept,
                              onChanged: _busy
                                  ? null
                                  : (_) => _toggleAutoAccept(d),
                            ),
                            const Divider(height: 8),
                            _row(
                              'Ví trên (COD giữ hộ)',
                              formatVnd(d.codBalance),
                            ),
                            _row(
                              'Ví thu nhập',
                              formatVnd(d.earningBalance),
                            ),
                            _row('Tổng chuyến', '${d.totalDeliveries}'),
                            _row(
                              'Đánh giá',
                              '${d.ratingAvg}★ (${d.ratingCount} lượt)',
                            ),
                            if (d.currentLatitude != null &&
                                d.currentLongitude != null)
                              _row(
                                'Vị trí gần nhất',
                                '${d.currentLatitude}, ${d.currentLongitude}'
                                '${d.locationUpdatedAt != null ? ' · ${formatDateTime(d.locationUpdatedAt!)}' : ''}',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/drivers/${d.id}/blocking-records'),
                      icon: const Icon(Icons.warning_amber_outlined),
                      label: const Text('Dữ liệu chặn xoá tài xế'),
                    ),
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
