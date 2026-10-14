import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/blindspot_chips.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../domain/digest.dart';

class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    required this.onTap,
    this.selected = false,
  });

  final Story story;
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
          padding: const EdgeInsets.all(16),
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
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${story.rank}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
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
              const SizedBox(height: 10),
              Text(
                Copy.outletCount(story.outletCount),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              CoverageIndicator(coverage: story.coverage),
              BlindspotChips(blindspot: story.blindspot),
            ],
          ),
        ),
      ),
    );
    // Null on phones and unselected rows, so they announce no selected state.
    return Semantics(selected: selected ? true : null, child: card);
  }
}
