import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bank.dart';
import '../../models/driver.dart';
import '../../models/driver_dispatch_settings.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import '../../core/responsive.dart';

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

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  bool _onlyUnverified = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).verifyDriver(d.id);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Admin sửa trực tiếp hồ sơ (CCCD, GPLX, xe, ngân hàng) — dùng khi tài xế nhờ chỉnh hộ, không
  /// đụng verified_at/rejected_at.
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
    final accountNumberCtrl = TextEditingController(
      text: d.bankAccountNumber ?? '',
    );
    final accountHolderCtrl = TextEditingController(
      text: d.bankAccountHolder ?? '',
    );
    var vehicleType = d.vehicleType ?? _vehicleTypeOptions.first.$1;
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

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateDriver(d.id, {
        'national_id': nationalIdCtrl.text.trim(),
        'license_no': licenseNoCtrl.text.trim(),
        'vehicle_type': vehicleType,
        'vehicle_plate': plateCtrl.text.trim(),
        if (selectedBank != null) 'bank_name': selectedBank!.name,
        if (selectedBank != null) 'bank_bin': selectedBank!.bin,
        'bank_account_number': accountNumberCtrl.text.trim(),
        'bank_account_holder': accountHolderCtrl.text.trim(),
      });
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).rejectDriver(d.id, finalReason);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Gỡ tài xế kẹt ở 1 trạng thái (thường 'busy') không tự nhận được chuyến mới — vd chuyến cũ
  /// bị xoá/đổi trạng thái ở màn "Chuyến giao hàng" nhưng vì lý do gì đó tài xế không tự về lại
  /// 'online'. Chỉ đổi đúng cột status của drivers, không đụng gì tới deliveries.
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

    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).forceDriverStatus(d.id, selected);
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Thêm/gỡ 1 tài xế khỏi nhóm "Tài xế dự phòng" (drivers.is_backup_driver) — nhóm này nhận
  /// không giới hạn đơn cùng lúc, chỉ được hệ thống mời khi không tìm được tài xế thường nào
  /// (xem server/src/dispatch.js) VÀ công tắc backupPoolEnabled đang bật.
  Future<void> _setBackup(Driver d, bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).updateDriver(d.id, {
        'is_backup_driver': value,
      });
      ref.invalidate(driversProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bật/tắt CẢ NHÓM tài xế dự phòng cùng lúc — tắt thì dù có tài xế nào trong danh sách cũng
  /// không được hệ thống mời, xem hofa-db/98_backup_driver_pool.sql.
  Future<void> _toggleBackupPoolEnabled(
    DriverDispatchSettings s,
    bool value,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepoProvider)
          .updateDriverDispatchSettings(
            DriverDispatchSettings(
              id: s.id,
              rescanIntervalSeconds: s.rescanIntervalSeconds,
              maxRescanAttempts: s.maxRescanAttempts,
              backupPoolEnabled: value,
            ),
          );
      ref.invalidate(driverDispatchSettingsProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driversProvider);
    final dispatchSettingsAsync = ref.watch(driverDispatchSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài xế'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(driversProvider),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tài xế'),
            Tab(text: 'Tài xế dự phòng'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: driversAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final normal = all.where((d) => !d.isBackupDriver).toList();
                final backup = all.where((d) => d.isBackupDriver).toList();
                return TabBarView(
                  controller: _tabController,
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('Chỉ hiện hồ sơ chưa duyệt'),
                                selected: _onlyUnverified,
                                onSelected: (v) =>
                                    setState(() => _onlyUnverified = v),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildDriverList(
                            _onlyUnverified
                                ? normal.where((d) => !d.isVerified).toList()
                                : normal,
                            emptyMessage: _onlyUnverified
                                ? 'Không có hồ sơ nào chờ duyệt'
                                : 'Chưa có tài xế nào',
                            statLabel: 'Tổng tài xế (đang lọc)',
                            inBackupTab: false,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tài xế trong danh sách này nhận KHÔNG GIỚI HẠN số đơn cùng lúc, '
                                'BẤT KỂ đang ở trạng thái nào (kể cả offline/đang bận) — chỉ '
                                'được hệ thống mời khi không tìm được tài xế thường nào nhận đơn.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 8),
                              dispatchSettingsAsync.when(
                                loading: () => const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                error: (e, _) => Text('Lỗi: $e'),
                                data: (s) => SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Kích hoạt nhóm tài xế dự phòng',
                                  ),
                                  subtitle: Text(
                                    s.backupPoolEnabled
                                        ? 'Đang hoạt động — tự mời khi không tìm được tài xế thường'
                                        : 'Đang tắt — nhóm này sẽ không được mời dù có tài xế trong danh sách',
                                  ),
                                  value: s.backupPoolEnabled,
                                  onChanged: _busy
                                      ? null
                                      : (v) => _toggleBackupPoolEnabled(s, v),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildDriverList(
                            backup,
                            emptyMessage:
                                'Chưa có tài xế nào trong danh sách dự phòng',
                            statLabel: 'Tổng tài xế dự phòng',
                            inBackupTab: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverList(
    List<Driver> list, {
    required String emptyMessage,
    required String statLabel,
    required bool inBackupTab,
  }) {
    final theme = Theme.of(context);
    if (list.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: list.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == list.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StatCard(
              label: statLabel,
              value: '${list.length}',
              icon: Icons.two_wheeler_outlined,
            ),
          );
        }
        final d = list[i];
        final verification = driverVerificationState(d);
        final (statusIcon, statusColor) = switch (verification) {
          DriverVerificationState.verified => (
            Icons.verified_user,
            Colors.green,
          ),
          DriverVerificationState.rejected => (
            Icons.block,
            theme.colorScheme.error,
          ),
          DriverVerificationState.pending => (Icons.pending, Colors.orange),
        };
        // Card tự dựng (không dùng ListTile.trailing) — trailing kiểu Row cứng
        // (tối đa 5 nút/chip) tràn ra ngoài trên màn hẹp vì ListTile không co giãn
        // trailing được; Wrap bên dưới title/subtitle tự xuống dòng khi hết chỗ.
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          child: InkWell(
            onTap: () => context.push('/drivers/${d.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message:
                            verification == DriverVerificationState.rejected
                            ? 'Bị từ chối: ${d.rejectionReason ?? ""}'
                            : '',
                        child: CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.12),
                          child: Icon(statusIcon, color: statusColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.fullName?.isNotEmpty == true
                                  ? d.fullName!
                                  : (d.phone ?? 'Tài xế'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${d.vehicleType ?? "Xe"} · ${d.vehiclePlate ?? "—"} · ${d.phone ?? "—"}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${d.totalDeliveries} chuyến · ${d.ratingAvg}★'
                              '${verification == DriverVerificationState.rejected ? ' · Bị từ chối: ${d.rejectionReason ?? ""}' : ''}',
                              style: TextStyle(
                                color:
                                    verification ==
                                        DriverVerificationState.rejected
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Sửa hồ sơ',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy ? null : () => _editProfile(d),
                      ),
                      IconButton(
                        tooltip: inBackupTab
                            ? 'Gỡ khỏi danh sách dự phòng'
                            : 'Thêm vào danh sách dự phòng',
                        icon: Icon(
                          inBackupTab
                              ? Icons.remove_moderator_outlined
                              : Icons.add_moderator_outlined,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _setBackup(d, !inBackupTab),
                      ),
                      ActionChip(
                        label: Text(driverStatusLabels[d.status] ?? d.status),
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _changeStatus(d),
                      ),
                      if (!d.isVerified) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: _busy ? null : () => _reject(d),
                          child: const Text('Từ chối'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _verify(d),
                          child: const Text('Duyệt hồ sơ'),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Đã duyệt',
                            style: TextStyle(color: Colors.green),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
