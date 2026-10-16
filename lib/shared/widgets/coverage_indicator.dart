import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../core/theme/app_theme.dart';
import '../../features/digest/domain/digest.dart';

/// Proportional bars for both axes: Left/Centre/Right and West/East.
///
/// One semantics node reads the counts in words, so screen-reader users get
/// the numbers rather than "image". [compact] (story cards) shows the bars
/// with their legends only; the full form (story page) names each axis.
class CoverageIndicator extends StatelessWidget {
  const CoverageIndicator({
    super.key,
    required this.coverage,
    this.compact = true,
  });

  final Coverage coverage;
  final bool compact;

  static String semanticsLabel(Coverage c) {
    final String lean = c.leanTotal == 0
        ? 'Coverage by political lean: no lean-rated outlets.'
        : 'Coverage by political lean: ${c.left} left, ${c.centre} centre, '
            '${c.right} right.';
    return '$lean Coverage by West and East: ${c.west} Western, '
        '${c.east} Eastern.';
  }

  @override
  Widget build(BuildContext context) {
    final PerspectiveColors colors = PerspectiveColors.of(context);
    return Semantics(
      container: true,
      label: semanticsLabel(coverage),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AxisRow(
              title: compact ? null : Copy.axisLean,
              segments: <_Segment>[
                for (final Lean l in Lean.values)
                  _Segment(l.label, coverage.forLean(l), colors.forLean(l)),
              ],
              emptyLabel: 'No lean-rated outlets',
              compact: compact,
            ),
            SizedBox(height: compact ? 8 : 14),
            _AxisRow(
              title: compact ? null : Copy.axisBloc,
              segments: <_Segment>[
                for (final Bloc b in Bloc.values)
                  _Segment(b.label, coverage.forBloc(b), colors.forBloc(b)),
              ],
              emptyLabel: 'No outlets',
              compact: compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment {
  const _Segment(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.title,
    required this.segments,
    required this.emptyLabel,
    required this.compact,
  });

  final String? title;
  final List<_Segment> segments;
  final String emptyLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final int total = segments.fold(0, (int s, _Segment x) => s + x.count);
    final double barHeight = compact ? 5 : 8;
    final TextStyle? legendStyle =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final Widget legend = total == 0
        ? Text(emptyLabel, style: legendStyle)
        : Wrap(
            spacing: 10,
            runSpacing: 2,
            children: <Widget>[
              for (final _Segment s in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.count == 0 ? colors.empty : s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${s.label} ${s.count}', style: legendStyle),
                  ],
                ),
            ],
          );

    final Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(barHeight),
      child: SizedBox(
        height: barHeight,
        child: total == 0
            ? ColoredBox(color: colors.empty)
            : Row(
                children: <Widget>[
                  for (final _Segment s in segments)
                    if (s.count > 0)
                      Expanded(
                        flex: s.count,
                        child: Container(
                          margin: const EdgeInsets.only(right: 1.5),
                          color: s.color,
                        ),
                      ),
                ],
              ),
      ),
    );

    if (title == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[bar, const SizedBox(height: 4), legend],
      );
    }
    // Axis name on the left, legend on the right; the legend drops to its
    // own line when the two do not fit (narrow phones, large text).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 2,
          children: <Widget>[
            Text(title!, style: theme.textTheme.labelLarge),
            legend,
          ],
        ),
        const SizedBox(height: 6),
        bar,
      ],
    );
  }
}
