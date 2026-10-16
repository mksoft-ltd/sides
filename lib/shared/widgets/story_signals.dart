import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../features/digest/domain/digest.dart';

/// What makes this story worth comparing, at a glance: blindspots ("Only
/// left-leaning outlets covered this"), and how many contested claims and
/// East–West contradictions the analysis found. Blindspots come from outlet
/// tags, the counts from validated analysis items; the chips never say who
/// is right.
class StorySignals extends StatelessWidget {
  const StorySignals({super.key, required this.story, this.topPadding = 10});

  final Story story;
  final double topPadding;

  List<_Signal> _signals() => <_Signal>[
        if (story.blindspot.lean case final Lean l)
          _Signal(Icons.visibility_off_outlined, Copy.blindspotLean(l)),
        if (story.blindspot.bloc case final Bloc b)
          _Signal(Icons.visibility_off_outlined, Copy.blindspotBloc(b)),
        if (story.analysisUnavailable)
          const _Signal(Icons.info_outline, Copy.analysisUnavailableShort)
        else ...<_Signal>[
          if (story.contestedClaims.isNotEmpty)
            _Signal(
              Icons.compare_arrows,
              Copy.contestedCount(story.contestedClaims.length),
            ),
          if (story.contradictions.isNotEmpty)
            _Signal(
              Icons.swap_horiz,
              Copy.contradictionCount(story.contradictions.length),
            ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final List<_Signal> signals = _signals();
    if (signals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final _Signal s in signals) SignalChip(icon: s.icon, text: s.text),
        ],
      ),
    );
  }
}

class _Signal {
  const _Signal(this.icon, this.text);
  final IconData icon;
  final String text;
}

/// A small, non-interactive chip with an icon and a label.
class SignalChip extends StatelessWidget {
  const SignalChip({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: cs.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
