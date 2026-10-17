import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/text/quotes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../../../shared/widgets/article_thumb.dart';
import '../../../../shared/widgets/outlet_avatar.dart';
import '../../../story/presentation/providers/story_view_controller.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';

/// "By side": the day's stories browsed by side, the way a news app's home
/// lists sections. One section per side present today (Left, Centre, Right,
/// then West, East), each a carousel of cards: the story, that side's lead
/// headline quote and the outlet it came from. A card opens the story on
/// the matching axis.
class SidesBrowseView extends ConsumerWidget {
  const SidesBrowseView({super.key, required this.onOpenStory});

  /// Opens a story on an axis.
  final void Function(Story story, PerspectiveAxis axis) onOpenStory;

  static Key sectionKey(String wire) => ValueKey<String>('side-section-$wire');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Digest? digest = ref.watch(
      digestControllerProvider.select((DigestState s) => s.digest),
    );
    if (digest == null) {
      return const MessageState(
        icon: Icons.view_agenda_outlined,
        title: 'No digest yet',
        message: 'Today\'s sides appear here once the digest has loaded.',
      );
    }
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final List<_SideSection> sections = <_SideSection>[
      for (final Lean l in Lean.values)
        _SideSection(
          wire: l.wire,
          label: Copy.leanGroup(l),
          color: colors.forLean(l),
          axis: PerspectiveAxis.lean,
          entries: <_Entry>[
            for (final Story s in digest.stories)
              if (s.framingFor(l) case final Framing<Lean> f)
                _Entry(story: s, quote: f.headlineQuotes.firstOrNull),
          ],
        ),
      for (final Bloc b in Bloc.values)
        _SideSection(
          wire: b.wire,
          label: Copy.blocGroup(b),
          color: colors.forBloc(b),
          axis: PerspectiveAxis.bloc,
          entries: <_Entry>[
            for (final Story s in digest.stories)
              if (s.framingForBloc(b) case final Framing<Bloc> f)
                _Entry(story: s, quote: f.headlineQuotes.firstOrNull),
          ],
        ),
    ].where((_SideSection s) => s.entries.isNotEmpty).toList();

    final ThemeData theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey<String>('sides-browse'),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(Copy.bySideTitle, style: theme.textTheme.headlineSmall),
              ),
              const SizedBox(height: 4),
              Text(
                Copy.bySideIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final _SideSection section in sections) ...<Widget>[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: section.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(section.label, style: theme.textTheme.titleMedium),
                  ),
                ),
                Text(
                  Copy.storyCount(section.entries.length),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            key: sectionKey(section.wire),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < section.entries.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 10),
                    _SideCard(
                      entry: section.entries[i],
                      color: section.color,
                      digest: digest,
                      onTap: () =>
                          onOpenStory(section.entries[i].story, section.axis),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SideSection {
  const _SideSection({
    required this.wire,
    required this.label,
    required this.color,
    required this.axis,
    required this.entries,
  });
  final String wire;
  final String label;
  final Color color;
  final PerspectiveAxis axis;
  final List<_Entry> entries;
}

class _Entry {
  const _Entry({required this.story, required this.quote});
  final Story story;
  final HeadlineQuote? quote;
}

/// A side's take on one story: the story title, the side's lead quote and
/// the outlet behind it.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.entry,
    required this.color,
    required this.digest,
    required this.onTap,
  });

  final _Entry entry;
  final Color color;
  final Digest digest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HeadlineQuote? q = entry.quote;
    final Article? article = q == null ? null : entry.story.article(q.articleId);
    final Outlet? outlet =
        article == null ? null : digest.outlet(article.outletId);
    return SizedBox(
      width: 260,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (article?.imageUrl != null) ...<Widget>[
                  ArticleThumb(
                    article: article!,
                    outlet: outlet,
                    width: 228,
                    height: 128,
                    radius: 10,
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  entry.story.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  q == null ? Copy.noneFound : Quotes.wrap(q.quote),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: q == null ? null : FontStyle.italic,
                  ),
                ),
                if (article != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      OutletAvatar(
                        outlet: outlet,
                        fallbackName: article.outletId,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          outlet?.name ?? article.outletId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
