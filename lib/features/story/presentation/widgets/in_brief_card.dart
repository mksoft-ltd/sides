import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../digest/domain/digest.dart';
import '../providers/story_view_controller.dart';
import 'points.dart';
import 'story_detail_view.dart' show SectionIcons;

/// Where a disagreement row sends the reader.
typedef JumpTo = void Function(String sectionId, PerspectiveAxis axis);

/// The top of a story in three parts: what happened (the pipeline's sourced
/// summary), where the views stand across the sides (its sourced
/// conclusion), and the list of disagreements the analysis found (contested
/// claims on the lean axis, East–West contradictions on the bloc axis), each
/// row jumping to its section.
///
/// Every part rests on cited articles like any other point. The card says
/// where the sides differ and never which side is right. Hidden when the
/// analysis is unavailable, and for an older digest (no summary, no
/// conclusion) with nothing contested.
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

    Widget part(String title, Widget body) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: 6),
              body,
            ],
          ),
        );

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.notes_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      Copy.inBrief,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatTiles(story: story),
            if (summary != null)
              part(
                Copy.summaryTitle,
                PointTile(point: summary, story: story, digest: digest),
              ),
            if (conclusion != null)
              part(
                Copy.conclusionTitle,
                PointTile(point: conclusion, story: story, digest: digest),
              ),
            part(
              Copy.disagreementsTitle,
              anyDisagreement
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final ContestedClaim c in story.contestedClaims)
                          _DisagreementRow(
                            label: Copy.contestedLabel,
                            text: c.claim,
                            onTap: () => onJump(
                              contestedSection,
                              PerspectiveAxis.lean,
                            ),
                          ),
                        for (final Contradiction x in story.contradictions)
                          _DisagreementRow(
                            label: Copy.contradictionLabel,
                            text: x.topic,
                            onTap: () => onJump(
                              contradictionsSection,
                              PerspectiveAxis.bloc,
                            ),
                          ),
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: NoneFound(text: Copy.noDisagreements),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three tiles: how much the sources agree on, how many claims are
/// contested, how many West–East contradictions. Counts of validated items.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.story});
  final Story story;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double gap = 8;
        // A layout swap can hand a transient near-zero width: never negative.
        final double w = c.maxWidth.isFinite
            ? math.max(0, (c.maxWidth - gap * 2) / 3)
            : 120;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            _StatTile(
              width: w,
              icon: SectionIcons.agreed,
              value: story.agreedFacts.length,
              label: Copy.tileAgreed,
            ),
            _StatTile(
              width: w,
              icon: SectionIcons.contested,
              value: story.contestedClaims.length,
              label: Copy.tileContested,
            ),
            _StatTile(
              width: w,
              icon: SectionIcons.contradictions,
              value: story.contradictions.length,
              label: Copy.tileContradictions,
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });
  final double width;
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 6),
            Text('$value', style: theme.textTheme.titleLarge),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
