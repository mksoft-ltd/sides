import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/side_pictures.dart';
import '../../../../shared/widgets/story_meta.dart';
import '../../domain/digest.dart';

/// How a story card is laid out in the feed (a news-app home page has one
/// large lead, a strip of top stories and compact rows for the rest).
enum StoryCardVariant {
  /// The default card: rank, title, bars and avatar strip, one line of facts.
  standard,

  /// The lead story: a dark plate with the headline and the summary, where
  /// a news app would put its photo.
  lead,

  /// A carousel card: rank, title, one line of facts; fixed width.
  compact,

  /// A list row: rank, title, one line of facts, a chevron.
  row,
}

/// One story in the digest. Every variant carries the rank badge, the
/// title, one plain line of facts and a [CoverageIndicator] (full on the
/// standard card, two slim bars elsewhere), and every variant is tappable
/// with a visible cue.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    required this.digest,
    required this.onTap,
    this.selected = false,
    this.variant = StoryCardVariant.standard,
  });

  final Story story;
  final Digest digest;
  final VoidCallback onTap;

  /// The story shown in the tablet detail pane: tinted, outlined and
  /// announced as selected.
  final bool selected;
  final StoryCardVariant variant;

  /// The brand plate (BRAND.md): the dark surface the lead card sits on.
  static const Color plateTop = Color(0xFF1D313A);
  static const Color plateBottom = Color(0xFF0F1C22);
  static const Color inkOnPlate = Color(0xFFEEF2F4);
  static const Color mutedOnPlate = Color(0xFFA7B3BB);

  static const double compactWidth = 250;

  @override
  Widget build(BuildContext context) {
    final Widget card = switch (variant) {
      StoryCardVariant.standard => _Standard(this),
      StoryCardVariant.lead => _Lead(this),
      StoryCardVariant.compact => _Compact(this),
      StoryCardVariant.row => _Row(this),
    };
    // Null on phones and unselected rows, so they announce no selected state.
    return Semantics(selected: selected ? true : null, child: card);
  }
}

/// The circled rank: neutral, colour is kept for the perspectives.
class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank, {this.onPlate = false});
  final int rank;
  final bool onPlate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Semantics(
      label: 'Story $rank',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onPlate
              ? StoryCard.inkOnPlate.withValues(alpha: 0.16)
              : cs.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$rank',
          style: theme.textTheme.labelLarge?.copyWith(
            color: onPlate ? StoryCard.inkOnPlate : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// "Compare coverage ›": the one cue that a card opens the comparison.
class _Cue extends StatelessWidget {
  const _Cue({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color c = color ?? theme.colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Flexible(
          child: Text(
            Copy.compare,
            style: theme.textTheme.labelLarge?.copyWith(color: c),
          ),
        ),
        Icon(Icons.chevron_right, size: 20, color: c),
      ],
    );
  }
}

class _Standard extends StatelessWidget {
  const _Standard(this.card);
  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Story story = card.story;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: card.selected ? cs.secondaryContainer : null,
      shape: card.selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: card.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _RankBadge(story.rank),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(story.title, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StoryMeta(story: story, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              CoverageIndicator(story: story, digest: card.digest),
              const SizedBox(height: 10),
              const _Cue(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lead story on the brand plate: eyebrow, big headline, the sourced
/// summary when the digest has one, one line of facts, two slim bars.
class _Lead extends StatelessWidget {
  const _Lead(this.card);
  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Story story = card.story;
    final ThemeData onPlate = theme.copyWith(
      extensions: <ThemeExtension<dynamic>>[PerspectiveColors.dark],
      colorScheme: theme.colorScheme.copyWith(
        onSurfaceVariant: StoryCard.mutedOnPlate,
        onSurface: StoryCard.inkOnPlate,
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      color: StoryCard.plateTop,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: card.onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[StoryCard.plateTop, StoryCard.plateBottom],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _RankBadge(story.rank, onPlate: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        Copy.leadStory,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: StoryCard.mutedOnPlate,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  story.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: StoryCard.inkOnPlate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (story.summary case final SourcedPoint s) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    s.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: StoryCard.inkOnPlate.withValues(alpha: 0.88),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Theme(
                  data: onPlate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SidePictures(
                        story: story,
                        digest: card.digest,
                        labelColor: StoryCard.mutedOnPlate,
                      ),
                      if (SidePictures.pick(story, card.digest).length >= 2)
                        const SizedBox(height: 14),
                      StoryMeta(story: story, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 10),
                      CoverageIndicator(
                        story: story,
                        digest: card.digest,
                        minimal: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _Cue(color: StoryCard.inkOnPlate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A carousel card of fixed width: rank, title, facts, slim bars, cue.
class _Compact extends StatelessWidget {
  const _Compact(this.card);
  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Story story = card.story;
    return SizedBox(
      width: StoryCard.compactWidth,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: card.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _RankBadge(story.rank),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        story.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StoryMeta(story: story, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                CoverageIndicator(story: story, digest: card.digest, minimal: true),
                const SizedBox(height: 8),
                const _Cue(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row: rank, title and facts, a chevron. The bars sit under the
/// facts, not beside the title, so the row reads left to right.
class _Row extends StatelessWidget {
  const _Row(this.card);
  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Story story = card.story;
    return InkWell(
      onTap: card.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _RankBadge(story.rank),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(story.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  StoryMeta(story: story, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    child: CoverageIndicator(
                      story: story,
                      digest: card.digest,
                      minimal: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right,
                size: 22,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
