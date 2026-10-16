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

/// The Search tab: a field, the matching stories from today and the
/// archive, and the option to have today's coverage of the topic analysed
/// when nothing in the archive fits.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key, required this.onOpenStory});

  /// Opens [story] from the digest held under [handle] (null = today's).
  final void Function(Story story, String? handle) onOpenStory;

  static const Key fieldKey = Key('search-field');
  static const Key analyseKey = Key('analyse-topic');

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

  void _submit() => ref.read(searchControllerProvider.notifier).search(_text.text);

  @override
  Widget build(BuildContext context) {
    final SearchState s = ref.watch(searchControllerProvider);
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
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
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  s.searching
                      ? Copy.searching
                      : Copy.searchResults(s.hits.length, s.daysSearched),
                  style: theme.textTheme.labelLarge?.copyWith(color: muted),
                ),
              ),
              if (s.searching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
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
              today: hit.digest.date == ref.watch(_todayDateProvider),
              onTap: () => widget.onOpenStory(
                hit.story,
                hit.digest.date == ref.read(_todayDateProvider)
                    ? null
                    : ExtraDigests.archiveHandle(hit.digest.date),
              ),
            ),
          ],
          if (!s.searching) ...<Widget>[
            const SizedBox(height: 20),
            _TopicPanel(
              state: s,
              onAnalyse: ref.read(searchControllerProvider.notifier).analyseTopic,
              onOpen: () => widget.onOpenStory(s.topicStory!, s.topicHandle),
            ),
          ],
        ],
      ],
    );
  }
}

/// Today's digest date, to tell a hit from today apart from an archive day.
final Provider<String?> _todayDateProvider = Provider<String?>(
  (Ref ref) => ref.watch(
    digestControllerProvider.select((DigestState s) => s.digest?.date),
  ),
);

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

/// "Analyse this topic": the on-demand path, with its states.
class _TopicPanel extends StatelessWidget {
  const _TopicPanel({
    required this.state,
    required this.onAnalyse,
    required this.onOpen,
  });
  final SearchState state;
  final VoidCallback onAnalyse;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color muted = cs.onSurfaceVariant;
    final Widget body = switch (state.topicPhase) {
      TopicPhase.idle || TopicPhase.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              state.hits.isEmpty ? Copy.topicPitchNoHits : Copy.topicPitch,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              Copy.topicNote,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (state.topicPhase == TopicPhase.failed) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.topicMessage ?? Copy.topicFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: SearchView.analyseKey,
              onPressed: onAnalyse,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                state.topicPhase == TopicPhase.failed
                    ? Copy.topicRetry
                    : Copy.topicAction,
              ),
            ),
          ],
        ),
      TopicPhase.working => Row(
          children: <Widget>[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(Copy.topicWorking, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      TopicPhase.ready => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              state.topicCached ? Copy.topicReadyCached : Copy.topicReady,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(state.topicStory!.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            StoryMeta(story: state.topicStory!),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.compare_arrows),
              label: const Text(Copy.compare),
            ),
          ],
        ),
      TopicPhase.noMatch =>
        Text(Copy.topicNoMatch, style: theme.textTheme.bodyMedium),
      TopicPhase.capped => Text(Copy.topicCapped, style: theme.textTheme.bodyMedium),
      TopicPhase.rateLimited =>
        Text(Copy.topicRateLimited, style: theme.textTheme.bodyMedium),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(Copy.topicTitle, style: theme.textTheme.titleMedium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}
