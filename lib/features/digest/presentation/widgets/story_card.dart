import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/story_signals.dart';
import '../../domain/digest.dart';

/// How a story card is laid out in the feed (a news-app home page has one
/// large lead, a strip of top stories and compact rows for the rest).
enum StoryCardVariant {
  /// The default card: rank, title, bars, avatar strip, signals, cue.
  standard,

  /// The lead story: a dark plate with the headline, the summary and the
  /// outlet strip, where a news app would put its photo.
  lead,

  /// A carousel card: rank, title and bars, fixed width.
  compact,

  /// A list row: title and a metadata line, with the bars at the right.
  row,
}

/// One story in the digest. Every variant carries the rank badge, the
/// title and a [CoverageIndicator], so each story is presented once and the
/// same way wherever it appears.
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

/// "15 outlets · 1 contested claim": the metadata line of a row.
String _metaLine(Story story) {
  final List<String> parts = <String>[Copy.outletCount(story.outletCount)];
  if (story.analysisUnavailable) {
    parts.add(Copy.analysisUnavailableShort);
  } else {
    if (story.contestedClaims.isNotEmpty) {
      parts.add(Copy.contestedCount(story.contestedClaims.length));
    }
    if (story.contradictions.isNotEmpty) {
      parts.add(Copy.contradictionCount(story.contradictions.length));
    }
  }
  if (story.blindspot.lean case final Lean l) parts.add(Copy.blindspotLean(l));
  if (story.blindspot.bloc case final Bloc b) parts.add(Copy.blindspotBloc(b));
  return parts.join(' · ');
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
              const SizedBox(height: 12),
              CoverageIndicator(story: story, digest: card.digest),
              StorySignals(story: story),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      Copy.outletCount(story.outletCount),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          Copy.compare,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.primary,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: cs.primary),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lead story on the brand plate: eyebrow, big headline, the sourced
/// summary when the digest has one, the outlet strip and the signals.
class _Lead extends StatelessWidget {
  const _Lead(this.card);
  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Story story = card.story;
    // On the dark plate the bars, legends and avatars use the dark theme's
    // perspective colours and the plate's muted ink.
    final ThemeData onPlate = theme.copyWith(
      extensions: <ThemeExtension<dynamic>>[PerspectiveColors.dark],
      colorScheme: theme.colorScheme.copyWith(
        onSurfaceVariant: StoryCard.mutedOnPlate,
        onSurface: StoryCard.inkOnPlate,
        surfaceContainerHighest: StoryCard.inkOnPlate.withValues(alpha: 0.16),
        secondaryContainer: StoryCard.inkOnPlate.withValues(alpha: 0.14),
        onSecondaryContainer: StoryCard.inkOnPlate,
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _RankBadge(story.rank, onPlate: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${Copy.leadStory} · ${Copy.outletCount(story.outletCount)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: StoryCard.mutedOnPlate,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  story.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: StoryCard.inkOnPlate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (story.summary case final SourcedPoint s) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    s.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: StoryCard.inkOnPlate.withValues(alpha: 0.86),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Theme(
                  data: onPlate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      CoverageIndicator(story: story, digest: card.digest),
                      StorySignals(story: story),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        Copy.compare,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: StoryCard.inkOnPlate,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: StoryCard.inkOnPlate,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A carousel card of fixed width: rank, title and the bars.
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                const SizedBox(height: 10),
                CoverageIndicator(story: story, digest: card.digest),
                const SizedBox(height: 8),
                Text(
                  _metaLine(story),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row: rank, title and metadata on the left, the bars on the right.
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _RankBadge(story.rank),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(story.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    Copy.outletCount(story.outletCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  StorySignals(story: story, topPadding: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 72,
                child: CoverageIndicator(
                  story: story,
                  digest: card.digest,
                  minimal: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
