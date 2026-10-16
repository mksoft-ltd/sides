import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/story_signals.dart';
import '../../domain/digest.dart';

/// One story in the digest list: rank and title, the coverage bars, the
/// signals that make it worth comparing (blindspots, contested claims,
/// contradictions), and the outlet count with a "Compare coverage" cue.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    required this.digest,
    required this.onTap,
    this.selected = false,
  });

  final Story story;
  final Digest digest;
  final VoidCallback onTap;

  /// The story shown in the tablet detail pane: tinted, outlined and
  /// announced as selected.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Widget card = Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? cs.secondaryContainer : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    label: 'Story ${story.rank}',
                    excludeSemantics: true,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        // Neutral: colour is kept for the perspectives (BRAND.md).
                        color: cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${story.rank}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(story.title, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CoverageIndicator(story: story, digest: digest),
              StorySignals(story: story),
              const SizedBox(height: 8),
              // Outlet count left, the cue right; the cue drops to its own
              // line when both do not fit (narrow phones, large text).
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
    // Null on phones and unselected rows, so they announce no selected state.
    return Semantics(selected: selected ? true : null, child: card);
  }
}
