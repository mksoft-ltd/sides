import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../data/digest_repository.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';
import 'digest_list_view.dart' show failureCopy, NoticeBanner;
import 'story_card.dart';

/// What the feed is filtered to. Every lens keeps the digest's rank order;
/// a lens only narrows which stories show.
enum FeedLens {
  all,
  contested,
  blindspots;

  String get label => switch (this) {
        FeedLens.all => Copy.lensAll,
        FeedLens.contested => Copy.lensContested,
        FeedLens.blindspots => Copy.lensBlindspots,
      };

  bool keeps(Story s) => switch (this) {
        FeedLens.all => true,
        FeedLens.contested =>
          s.contestedClaims.isNotEmpty || s.contradictions.isNotEmpty,
        FeedLens.blindspots => s.blindspot.any,
      };
}

final NotifierProvider<FeedLensController, FeedLens> feedLensProvider =
    NotifierProvider<FeedLensController, FeedLens>(FeedLensController.new);

class FeedLensController extends Notifier<FeedLens> {
  @override
  FeedLens build() => FeedLens.all;
  void set(FeedLens lens) => state = lens;
}

/// The phone home feed, laid out like a news app's front page: the date,
/// a lens chip row, the lead story on the brand plate, a "Top stories"
/// carousel, then the rest as rows. Each story appears exactly once.
class DigestFeedView extends ConsumerWidget {
  const DigestFeedView({super.key, required this.onOpenStory});

  final ValueChanged<Story> onOpenStory;

  static const int carouselCount = 3;
  static const Key carouselKey = Key('top-stories-carousel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DigestState state = ref.watch(digestControllerProvider);
    final DigestController controller =
        ref.read(digestControllerProvider.notifier);
    final LoadedDigest? loaded = state.loaded;

    if (loaded == null) {
      if (state.initialising || state.refreshing || state.lastFailure == null) {
        return const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading today\'s digest',
          ),
        );
      }
      final ({String title, String message}) copy =
          failureCopy(state.lastFailure!, hasCache: false);
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: MessageState(
          icon: state.lastFailure == RefreshFailureKind.offline
              ? Icons.cloud_off_outlined
              : Icons.error_outline,
          title: copy.title,
          message: copy.message,
          actionLabel: 'Retry',
          onAction: controller.refresh,
        ),
      );
    }

    final Digest digest = loaded.digest;
    final FeedLens lens = ref.watch(feedLensProvider);
    final List<Story> stories =
        digest.stories.where(lens.keeps).toList(growable: false);
    final Story? lead = stories.firstOrNull;
    final List<Story> top = stories.skip(1).take(carouselCount).toList();
    final List<Story> rest = stories.skip(1 + carouselCount).toList();
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('digest-feed'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _FeedHeader(digest: digest, failure: state.lastFailure),
          ),
          const SizedBox(height: 10),
          _LensRow(lens: lens, onChanged: ref.read(feedLensProvider.notifier).set),
          const SizedBox(height: 12),
          if (lead == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Text(
                Copy.lensEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StoryCard(
                story: lead,
                digest: digest,
                variant: StoryCardVariant.lead,
                onTap: () => onOpenStory(lead),
              ),
            ),
          if (top.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            const _SectionTitle(Copy.topStories),
            const SizedBox(height: 10),
            // Not a lazy list: three cards, all built, equal height, so the
            // strip sizes to its content at any text scale.
            SingleChildScrollView(
              key: carouselKey,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < top.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 10),
                      StoryCard(
                        story: top[i],
                        digest: digest,
                        variant: StoryCardVariant.compact,
                        onTap: () => onOpenStory(top[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (rest.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            const _SectionTitle(Copy.moreStories),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < rest.length; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    StoryCard(
                      story: rest[i],
                      digest: digest,
                      variant: StoryCardVariant.row,
                      onTap: () => onOpenStory(rest[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.digest, required this.failure});
  final Digest digest;
  final RefreshFailureKind? failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? day = DateTime.tryParse(digest.date);
    final String dayLabel =
        day == null ? digest.date : DateFormat('EEEE d MMMM y').format(day);
    final String updated =
        DateFormat('d MMM y, HH:mm').format(digest.generatedAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (failure != null) ...<Widget>[
          NoticeBanner(
            text: failureCopy(failure!, hasCache: true).message,
            offline: failure == RefreshFailureKind.offline,
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(dayLabel, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 4),
        Text(
          'Last updated $updated · ${digest.stories.length} top stories',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// "All · Contested · Blindspots": narrows the feed.
class _LensRow extends StatelessWidget {
  const _LensRow({required this.lens, required this.onChanged});
  final FeedLens lens;
  final ValueChanged<FeedLens> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (final FeedLens l in FeedLens.values) ...<Widget>[
            if (l != FeedLens.values.first) const SizedBox(width: 8),
            ChoiceChip(
              key: ValueKey<String>('lens-${l.name}'),
              label: Text(l.label),
              selected: l == lens,
              onSelected: (_) => onChanged(l),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}
