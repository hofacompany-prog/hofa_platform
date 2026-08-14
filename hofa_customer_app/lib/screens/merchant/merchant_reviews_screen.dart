import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../providers/app_providers.dart';
import '../../widgets/full_screen_gallery_viewer.dart';
import '../../widgets/network_image_box.dart';

/// Danh sách đánh giá của 1 cửa hàng, có lọc theo số sao — mở từ dòng sao ở
/// merchant_detail_screen.dart. Tải dần theo trang, đổi bộ lọc tự về trang đầu (key family đổi).
class MerchantReviewsScreen extends ConsumerStatefulWidget {
  final String merchantId;
  const MerchantReviewsScreen({super.key, required this.merchantId});

  @override
  ConsumerState<MerchantReviewsScreen> createState() =>
      _MerchantReviewsScreenState();
}

class _MerchantReviewsScreenState extends ConsumerState<MerchantReviewsScreen> {
  int? _ratingFilter;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(
            merchantReviewsPagedProvider((
              widget.merchantId,
              _ratingFilter,
            )).notifier,
          )
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final merchantAsync = ref.watch(merchantDetailProvider(widget.merchantId));
    final reviewsState = ref.watch(
      merchantReviewsPagedProvider((widget.merchantId, _ratingFilter)),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Đánh giá cửa hàng'),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          merchantAsync.maybeWhen(
            data: (m) => Row(
              children: [
                Icon(Icons.star, color: Colors.amber.shade700, size: 28),
                const SizedBox(width: 8),
                Text(
                  m.ratingAvg.toStringAsFixed(1),
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                Text(
                  '(${m.ratingCount} đánh giá)',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            orElse: () => const SizedBox(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(
                  label: 'Tất cả',
                  selected: _ratingFilter == null,
                  onTap: () => setState(() => _ratingFilter = null),
                ),
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _filterChip(
                      label: '$star ★',
                      selected: _ratingFilter == star,
                      onTap: () => setState(() => _ratingFilter = star),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (reviewsState.isInitialLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (reviewsState.error != null)
            Text('Lỗi: ${reviewsState.error}')
          else if (reviewsState.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Chưa có đánh giá nào')),
            )
          else
            ...reviewsState.items.map(
              (r) => Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.customerName?.isNotEmpty == true
                                  ? r.customerName!
                                  : 'Khách hàng',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            formatDateTime(r.createdAt),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < r.rating ? Icons.star : Icons.star_border,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                      if (r.comment != null && r.comment!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(r.comment!),
                      ],
                      if (r.mediaUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: r.mediaUrls.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, i) => InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => FullScreenGalleryViewer.open(
                                context,
                                images: r.mediaUrls,
                                initialIndex: i,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: NetworkImageBox(
                                  url: r.mediaUrls[i],
                                  width: 72,
                                  height: 72,
                                  fallbackIcon: Icons.image_outlined,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (r.merchantReply != null &&
                          r.merchantReply!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Phản hồi từ cửa hàng',
                                style: theme.textTheme.labelSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.merchantReply!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (reviewsState.isLoadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}
