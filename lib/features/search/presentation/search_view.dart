import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/copy.dart';
import '../../../shared/widgets/story_meta.dart';
import '../../digest/domain/digest.dart';
import '../../digest/presentation/providers/digest_controller.dart';
import '../../digest/presentation/widgets/story_card.dart';
import '../domain/search.dart';
import 'search_controller.dart';
import 'search_progress.dart';

/// The Search tab: one field. Results come from the cheapest source first
/// (this phone, then the archive online, then the shared cache, and only if
/// today has nothing, a new comparison) and stream into one list. A search
/// that takes more than half a second shows what it is doing.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key, required this.onOpenStory});

  /// Opens [story] from the digest held under [handle] (null = today's).
  final void Function(Story story, String? handle) onOpenStory;

  static const Key fieldKey = Key('search-field');
  static const Key topicCardKey = Key('topic-result');
  static const Key retryKey = Key('search-retry');

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  late final TextEditingController _text = TextEditingController(
    text: ref.read(searchControllerProvider).query,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider.notifier).search(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final SearchState s = ref.watch(searchControllerProvider);
    final String? todayDate = ref.watch(
      digestControllerProvider.select((DigestState d) => d.digest?.date),
    );
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final bool nothing =
        !s.searching && s.hits.isEmpty && s.topicPhase != TopicPhase.ready;

    return ListView(
      key: const PageStorageKey<String>('search'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(Copy.searchTitle, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 4),
        Text(
          Copy.searchIntro,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        TextField(
          key: SearchView.fieldKey,
          controller: _text,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: Copy.searchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: Copy.searchAction,
              icon: const Icon(Icons.arrow_forward),
              onPressed: _submit,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
        if (s.hasQuery) ...<Widget>[
          if (s.searching) ...<Widget>[
            const SizedBox(height: 16),
            // A fresh panel per query, so its half-second delay restarts.
            SearchProgress(key: ValueKey<String>('p-${s.query}'), state: s),
          ],
          if (s.topicPhase == TopicPhase.ready) ...<Widget>[
            const SizedBox(height: 16),
            _TopicCard(
              story: s.topicStory!,
              cached: s.topicCached,
              onTap: () => widget.onOpenStory(s.topicStory!, s.topicHandle),
            ),
          ],
          if (s.hits.isNotEmpty || !s.searching) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              Copy.searchResults(s.hits.length, s.daysSearched),
              style: theme.textTheme.labelLarge?.copyWith(color: muted),
            ),
          ],
          if (s.archiveUnavailable && !s.searching) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              Copy.archiveUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          for (final SearchHit hit in s.hits) ...<Widget>[
            const SizedBox(height: 12),
            _HitCard(
              hit: hit,
              today: hit.digest.date == todayDate,
              onTap: () => widget.onOpenStory(
                hit.story,
                hit.digest.date == todayDate
                    ? null
                    : ExtraDigests.archiveHandle(hit.digest.date),
              ),
            ),
          ],
          if (s.searching && s.hits.isEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const ResultSkeleton(),
            const SizedBox(height: 12),
            const ResultSkeleton(),
          ],
          if (!s.searching) ...<Widget>[
            const SizedBox(height: 16),
            _Outcome(state: s, nothing: nothing),
          ],
        ],
      ],
    );
  }
}

/// The comparison, at the top of the results.
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.story,
    required this.cached,
    required this.onTap,
  });
  final Story story;
  final bool cached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Card(
      key: SearchView.topicCardKey,
      color: cs.secondaryContainer.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      cached ? Copy.topicCardCached : Copy.topicCardLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(story.title, style: theme.textTheme.titleMedium),
                    if (story.summary case final SourcedPoint p) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        p.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 8),
                    StoryMeta(story: story, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit, required this.today, required this.onTap});
  final SearchHit hit;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? day = DateTime.tryParse(hit.digest.date);
    final String when = today
        ? Copy.today
        : (day == null ? hit.digest.date : DateFormat('EEE d MMM').format(day));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              when,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StoryCard(
              story: hit.story,
              digest: hit.digest,
              variant: StoryCardVariant.row,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// What happened when the search finished, only when there is something to
/// say: nothing found, the daily limit, or a failed comparison.
class _Outcome extends ConsumerWidget {
  const _Outcome({required this.state, required this.nothing});
  final SearchState state;
  final bool nothing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String? text = switch (state.topicPhase) {
      TopicPhase.capped => Copy.topicCapped,
      TopicPhase.rateLimited => Copy.topicRateLimited,
      TopicPhase.failed => state.topicMessage ?? Copy.topicFailed,
      _ => nothing ? Copy.searchNothing : null,
    };
    if (text == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(text, style: style),
        if (state.topicPhase == TopicPhase.failed)
          TextButton(
            key: SearchView.retryKey,
            onPressed: ref.read(searchControllerProvider.notifier).retry,
            child: const Text(Copy.topicRetry),
          ),
      ],
    );
  }
}
