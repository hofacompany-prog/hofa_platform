import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_version_text.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final driverAsync = ref.watch(myDriverProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                            child: Icon(Icons.person, color: theme.colorScheme.primary, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.fullName, style: theme.textTheme.titleMedium),
                                Text(profile.phone, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      driverAsync.when(
                        loading: () => const SizedBox(),
                        error: (_, _) => const SizedBox(),
                        data: (driver) => driver == null
                            ? const SizedBox()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _row(context, 'Loại xe', driver.vehicleType ?? '—'),
                                  _row(context, 'Biển số', driver.vehiclePlate ?? '—'),
                                  _row(context, 'Số GPLX', driver.licenseNo ?? '—'),
                                  _row(context, 'Trạng thái hồ sơ', driver.isVerified ? 'Đã duyệt' : 'Chờ duyệt'),
                                  _row(context, 'Đánh giá', '${driver.ratingAvg}★ (${driver.ratingCount} lượt)'),
                                  _row(context, 'Tổng chuyến', '${driver.totalDeliveries}'),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
              const SizedBox(height: 12),
              const AppVersionText(),
            ],
          );
        },
      ),
    );
  }
}
