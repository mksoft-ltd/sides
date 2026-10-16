import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../digest/domain/digest.dart';
import '../providers/story_view_controller.dart';
import 'points.dart';

/// Where a disagreement row sends the reader.
typedef JumpTo = void Function(String sectionId, PerspectiveAxis axis);

/// The top of a story, as reading text: what happened (the pipeline's
/// sourced summary), where the views stand across the sides (its sourced
/// conclusion), one line of counts, and the disagreements the analysis
/// found as rows that jump to their section. Every paragraph rests on cited
/// articles like any other point. The card says where the sides differ and
/// never which side is right. Hidden when the analysis is unavailable, and
/// for an older digest (no summary, no conclusion) with nothing contested.
class InBriefCard extends StatelessWidget {
  const InBriefCard({
    super.key,
    required this.story,
    required this.digest,
    required this.onJump,
  });

  final Story story;
  final Digest digest;
  final JumpTo onJump;

  static const Key cardKey = Key('in-brief');
  static const String contestedSection = 'contested';
  static const String contradictionsSection = 'contradictions';

  @override
  Widget build(BuildContext context) {
    final SourcedPoint? summary = story.summary;
    final SourcedPoint? conclusion = story.conclusion;
    final bool anyDisagreement =
        story.contestedClaims.isNotEmpty || story.contradictions.isNotEmpty;
    if (story.analysisUnavailable ||
        (summary == null && conclusion == null && !anyDisagreement)) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;

    Widget heading(String text) => Semantics(
          header: true,
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(color: muted),
          ),
        );

    return Column(
      key: cardKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (summary != null) ...<Widget>[
          heading(Copy.summaryTitle),
          const SizedBox(height: 6),
          PointTile(point: summary, story: story, digest: digest, last: true),
          const SizedBox(height: 18),
        ],
        if (conclusion != null) ...<Widget>[
          heading(Copy.conclusionTitle),
          const SizedBox(height: 6),
          PointTile(point: conclusion, story: story, digest: digest, last: true),
          const SizedBox(height: 18),
        ],
        heading(Copy.disagreementsTitle),
        const SizedBox(height: 6),
        _CountsLine(story: story),
        if (anyDisagreement) ...<Widget>[
          const SizedBox(height: 4),
          for (final ContestedClaim c in story.contestedClaims)
            _DisagreementRow(
              label: Copy.contestedLabel,
              text: c.claim,
              onTap: () => onJump(contestedSection, PerspectiveAxis.lean),
            ),
          for (final Contradiction x in story.contradictions)
            _DisagreementRow(
              label: Copy.contradictionLabel,
              text: x.topic,
              onTap: () => onJump(contradictionsSection, PerspectiveAxis.bloc),
            ),
        ],
      ],
    );
  }
}

/// "Agree on 5 points · 1 contested claim · no East–West contradictions".
class _CountsLine extends StatelessWidget {
  const _CountsLine({required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? s = theme.textTheme.bodyMedium;
    final List<String> items = <String>[
      Copy.agreedCount(story.agreedFacts.length),
      story.contestedClaims.isEmpty
          ? Copy.noContested
          : Copy.contestedCount(story.contestedClaims.length),
      story.contradictions.isEmpty
          ? Copy.noContradictionsShort
          : Copy.contradictionCount(story.contradictions.length),
    ];
    return Wrap(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) Text('  ·  ', style: s),
          Text(items[i], style: s),
        ],
      ],
    );
  }
}

/// One disagreement: a small kind label, the claim or topic, and a chevron.
/// Tapping it scrolls to the section (switching axis when needed).
class _DisagreementRow extends StatelessWidget {
  const _DisagreementRow({
    required this.label,
    required this.text,
    required this.onTap,
  });

  final String label;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$label: $text. Jumps to the section.',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(text, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, size: 22, color: cs.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
