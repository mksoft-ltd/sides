import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../features/digest/domain/digest.dart';

/// One muted line of facts about a story: outlet count, contested claims,
/// East–West contradictions, blindspots. Plain text, no chips: each fact is
/// its own [Text] (joined by middle dots) so a screen reader and a test see
/// each one whole. Counts of validated items; never a judgement.
class StoryMeta extends StatelessWidget {
  const StoryMeta({
    super.key,
    required this.story,
    this.color,
    this.style,
    this.includeOutlets = true,
  });

  final Story story;
  final Color? color;
  final TextStyle? style;
  final bool includeOutlets;

  static List<String> facts(Story story, {bool includeOutlets = true}) =>
      <String>[
        if (includeOutlets) Copy.outletCount(story.outletCount),
        if (story.analysisUnavailable)
          Copy.analysisUnavailableShort
        else ...<String>[
          if (story.contestedClaims.isNotEmpty)
            Copy.contestedCount(story.contestedClaims.length),
          if (story.contradictions.isNotEmpty)
            Copy.contradictionCount(story.contradictions.length),
        ],
        if (story.blindspot.lean case final Lean l) Copy.blindspotLean(l),
        if (story.blindspot.bloc case final Bloc b) Copy.blindspotBloc(b),
      ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? s = (style ?? theme.textTheme.bodyMedium)?.copyWith(
      color: color ?? theme.colorScheme.onSurfaceVariant,
    );
    final List<String> items = facts(story, includeOutlets: includeOutlets);
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) Text('  ·  ', style: s),
          Text(items[i], style: s),
        ],
      ],
    );
  }
}
