import 'package:flutter/material.dart';

import '../../core/constants/copy.dart';
import '../../core/theme/app_theme.dart';
import '../../features/digest/domain/digest.dart';
import 'motion.dart';
import 'outlet_avatar.dart';

/// Who covered the story, on both axes.
///
/// Compact (story cards): proportional bars for Left/Centre/Right and
/// West/East, then one strip of outlet avatars ordered left to right (and
/// West before East for outlets off the lean scale).
///
/// Full (story page): a "spectrum": three zones Left · Centre · Right, each
/// holding that side's outlets as avatars, then two zones West · East. A
/// zone is tappable when [onSideTap] is given (e.g. opens that side's
/// articles).
///
/// One semantics node reads the counts in words, so screen-reader users get
/// the numbers rather than "image"; the avatars are excluded.
class CoverageIndicator extends StatelessWidget {
  const CoverageIndicator({
    super.key,
    required this.story,
    required this.digest,
    this.compact = true,
    this.minimal = false,
    this.onSideTap,
  });

  final Story story;
  final Digest digest;
  final bool compact;

  /// Compact mode with the bars only (no legend, no avatars): for a narrow
  /// slot such as a list row's trailing box.
  final bool minimal;

  /// Full mode only: tapping a side's zone, with that side's outlets.
  final void Function(String side, List<Outlet> outlets)? onSideTap;

  static String semanticsLabel(Coverage c) {
    final String lean = c.leanTotal == 0
        ? 'Coverage by political lean: no lean-rated outlets.'
        : 'Coverage by political lean: ${c.left} left, ${c.centre} centre, '
            '${c.right} right.';
    return '$lean Coverage by West and East: ${c.west} Western, '
        '${c.east} Eastern.';
  }

  /// The story's distinct outlets, in the digest's order (by id).
  List<Outlet> _outlets() {
    final Map<String, Outlet> seen = <String, Outlet>{};
    for (final Article a in story.articles) {
      final Outlet? o = digest.outlet(a.outletId);
      if (o != null) seen[o.id] = o;
    }
    final List<Outlet> out = seen.values.toList()
      ..sort((Outlet a, Outlet b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final Coverage coverage = story.coverage;
    final List<Outlet> outlets = _outlets();
    final Widget body = compact
        ? _Compact(
            coverage: coverage,
            outlets: outlets,
            colors: colors,
            minimal: minimal,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Spectrum(
                title: Copy.axisLean,
                zones: <_Zone>[
                  for (final Lean l in Lean.values)
                    _Zone(
                      label: l.label,
                      count: coverage.forLean(l),
                      color: colors.forLean(l),
                      outlets: outlets
                          .where((Outlet o) => o.lean == l)
                          .toList(),
                    ),
                ],
                emptyLabel: 'No lean-rated outlets',
                onSideTap: onSideTap,
              ),
              const SizedBox(height: 14),
              _Spectrum(
                title: Copy.axisBloc,
                zones: <_Zone>[
                  for (final Bloc b in Bloc.values)
                    _Zone(
                      label: b.label,
                      count: coverage.forBloc(b),
                      color: colors.forBloc(b),
                      outlets: outlets
                          .where((Outlet o) => o.bloc == b)
                          .toList(),
                    ),
                ],
                emptyLabel: 'No outlets',
                onSideTap: onSideTap,
              ),
            ],
          );
    return Semantics(
      container: true,
      label: semanticsLabel(coverage),
      child: ExcludeSemantics(child: body),
    );
  }
}

class _Zone {
  const _Zone({
    required this.label,
    required this.count,
    required this.color,
    required this.outlets,
  });
  final String label;
  final int count;
  final Color color;
  final List<Outlet> outlets;
}

/// Full mode: the axis name, then one zone per side with a rail in the
/// side's colour, its avatars and "Left 6" beneath.
class _Spectrum extends StatelessWidget {
  const _Spectrum({
    required this.title,
    required this.zones,
    required this.emptyLabel,
    required this.onSideTap,
  });

  final String title;
  final List<_Zone> zones;
  final String emptyLabel;
  final void Function(String side, List<Outlet> outlets)? onSideTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final int total = zones.fold(0, (int s, _Zone z) => s + z.count);
    final TextStyle? caption = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        if (total == 0)
          Text(emptyLabel, style: caption)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < zones.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ZoneBox(
                    zone: zones[i],
                    empty: colors.empty,
                    caption: caption,
                    onTap: onSideTap == null || zones[i].outlets.isEmpty
                        ? null
                        : () => onSideTap!(zones[i].label, zones[i].outlets),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// One side of a spectrum: a rail in the side's colour, its outlets as a
/// dense grid of avatars, and "Left 6" beneath. The whole zone is the tap
/// target (48 dp tall at least), so the avatars can sit close together.
class _ZoneBox extends StatelessWidget {
  const _ZoneBox({
    required this.zone,
    required this.empty,
    required this.caption,
    required this.onTap,
  });

  final _Zone zone;
  final Color empty;
  final TextStyle? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget body = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: zone.count == 0 ? empty : zone.color,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (int i = 0; i < zone.outlets.length; i++)
                PopIn(
                  index: i,
                  child: OutletAvatar(outlet: zone.outlets[i], size: 28),
                ),
              if (zone.outlets.isEmpty) const SizedBox(height: 28),
            ],
          ),
          const SizedBox(height: 6),
          Text('${zone.label} ${zone.count}', style: caption),
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: '${zone.label}: ${zone.outlets.map((Outlet o) => o.name).join(', ')}. '
          'Shows their articles.',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: zone.outlets.map((Outlet o) => o.name).join(', '),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: body,
        ),
      ),
    );
  }
}

/// Compact mode: the two proportional bars with their legends, then the
/// outlets as a single strip of small avatars, left to right.
class _Compact extends StatelessWidget {
  const _Compact({
    required this.coverage,
    required this.outlets,
    required this.colors,
    this.minimal = false,
  });
  final Coverage coverage;
  final List<Outlet> outlets;
  final PerspectiveColors colors;
  final bool minimal;

  @override
  Widget build(BuildContext context) {
    final List<Outlet> ordered = <Outlet>[...outlets]..sort(
        (Outlet a, Outlet b) {
          int key(Outlet o) => o.lean?.index ?? (3 + o.bloc.index);
          final int c = key(a).compareTo(key(b));
          return c != 0 ? c : a.name.compareTo(b.name);
        },
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Bar(
          segments: <_Segment>[
            for (final Lean l in Lean.values)
              _Segment(l.label, coverage.forLean(l), colors.forLean(l)),
          ],
          emptyLabel: 'No lean-rated outlets',
          empty: colors.empty,
          legend: !minimal,
        ),
        SizedBox(height: minimal ? 6 : 8),
        _Bar(
          segments: <_Segment>[
            for (final Bloc b in Bloc.values)
              _Segment(b.label, coverage.forBloc(b), colors.forBloc(b)),
          ],
          emptyLabel: 'No outlets',
          empty: colors.empty,
          legend: !minimal,
        ),
        if (!minimal && ordered.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: <Widget>[
              for (final Outlet o in ordered) OutletAvatar(outlet: o, size: 20),
            ],
          ),
        ],
      ],
    );
  }
}

class _Segment {
  const _Segment(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.segments,
    required this.emptyLabel,
    required this.empty,
    this.legend = true,
  });

  final List<_Segment> segments;
  final String emptyLabel;
  final Color empty;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = segments.fold(0, (int s, _Segment x) => s + x.count);
    final TextStyle? legendStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 5,
            child: total == 0
                ? ColoredBox(color: empty)
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
        ),
        if (!legend)
          const SizedBox.shrink()
        else if (total == 0) ...<Widget>[
          const SizedBox(height: 4),
          Text(emptyLabel, style: legendStyle),
        ] else ...<Widget>[
          const SizedBox(height: 4),
          Wrap(
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
                        color: s.count == 0 ? empty : s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${s.label} ${s.count}', style: legendStyle),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
