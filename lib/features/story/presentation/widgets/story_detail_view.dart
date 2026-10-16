import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/motion.dart';
import '../../../../shared/widgets/report_story_tile.dart';
import '../../../../shared/widgets/section.dart';
import '../../../../shared/widgets/story_meta.dart';
import '../../../digest/domain/digest.dart';
import '../providers/story_view_controller.dart';
import 'in_brief_card.dart';
import 'points.dart';
import 'source_pills.dart';
import 'sources_list.dart';

export '../providers/story_view_controller.dart' show PerspectiveAxis;

/// The whole story page without a scaffold: the phone page and the tablet
/// detail pane both host it. The axis choice lives in [storyViewProvider],
/// so swapping layouts keeps the reader's place.
///
/// The comparison is organised by what is compared, not by side: every
/// section ("Headlines, side by side", "What each side emphasises") shows
/// every side at once, stacked with a colour rail each, or — at
/// [LayoutSize.expanded] when every column still gets [minColumnWidth] at
/// the current text scale — as side-by-side columns (see [columnsFit]).
/// A jump bar under the axis switch lists the sections with their counts.
class StoryDetailView extends ConsumerStatefulWidget {
  const StoryDetailView({
    super.key,
    required this.story,
    required this.digest,
    this.initialAxis = PerspectiveAxis.lean,
  });

  final Story story;
  final Digest digest;

  /// The route's axis (`?axis=bloc`); applies until the reader switches.
  final PerspectiveAxis initialAxis;

  /// Narrowest perspective column, in dp at text scale 1.0. Scaled with the
  /// text, so at 200% a column needs 560 dp or the view falls back to
  /// stacked sides.
  static const double minColumnWidth = 280;
  static const double columnGap = ContradictionCard.columnGap;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(16, 8, 16, 32);

  static const Key noContradictionsKey = Key('no-contradictions');
  static const Key analysisUnavailableKey = Key('analysis-unavailable');

  /// Whether [count] columns fit side by side in [width] (the content width,
  /// padding already removed) at this context's text scale.
  static bool columnsFit(BuildContext context, double width, int count) {
    if (count < 1) return false;
    final double min = MediaQuery.textScalerOf(context).scale(minColumnWidth);
    return (width - columnGap * (count - 1)) / count >= min;
  }

  @override
  ConsumerState<StoryDetailView> createState() => _StoryDetailViewState();
}

class _StoryDetailViewState extends ConsumerState<StoryDetailView> {
  /// One anchor per section per axis; the jump bar scrolls to them. The
  /// page is a single column (not a lazy list) so every anchor is always
  /// laid out. Keys are per axis because, while the axis switch animates,
  /// both axes' sections are in the tree at once.
  final Map<String, GlobalKey> _anchors = <String, GlobalKey>{};

  /// The section briefly highlighted after a jump, by anchor key.
  String? _flash;
  Timer? _flashTimer;

  /// The axis last built, to pick the slide direction of the switch.
  PerspectiveAxis? _lastAxis;

  static String _anchorId(String id, PerspectiveAxis? axis) =>
      id == _Jump.sources ? 'shared-$id' : '${axis!.name}-$id';

  GlobalKey _anchor(String id, PerspectiveAxis? axis) =>
      _anchors.putIfAbsent(_anchorId(id, axis), GlobalKey.new);

  PerspectiveAxis get _axis =>
      ref.read(storyViewProvider(story.id)).axisOr(widget.initialAxis);

  void _jumpTo(String id, [PerspectiveAxis? axis]) {
    final String key = _anchorId(id, axis ?? _axis);
    final BuildContext? target = _anchors[key]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (Motion.reduced(context)) return;
    _flashTimer?.cancel();
    setState(() => _flash = key);
    _flashTimer = Timer(Motion.flash, () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  /// A disagreement row in the "In brief" card: switch axis when the target
  /// section lives on the other one, then scroll once that axis has built.
  void _jumpOnAxis(String id, PerspectiveAxis axis) {
    final StoryViewController controller = ref.read(
      storyViewProvider(story.id).notifier,
    );
    final PerspectiveAxis current = ref
        .read(storyViewProvider(story.id))
        .axisOr(widget.initialAxis);
    if (current == axis) {
      _jumpTo(id, axis);
      return;
    }
    controller.setAxis(axis);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpTo(id, axis);
    });
  }

  Story get story => widget.story;
  Digest get digest => widget.digest;

  @override
  Widget build(BuildContext context) {
    final StoryViewState view = ref.watch(storyViewProvider(story.id));
    final StoryViewController controller = ref.read(
      storyViewProvider(story.id).notifier,
    );
    final PerspectiveAxis axis = view.axisOr(widget.initialAxis);
    final bool expanded = LayoutSize.of(context) == LayoutSize.expanded;
    final ThemeData theme = Theme.of(context);
    final int unrated = story.outletCount - story.coverage.leanTotal;
    // Slide direction for the axis switch: West / East sits to the right.
    final bool forward = _lastAxis == null || axis.index >= _lastAxis!.index;
    _lastAxis = axis;
    int step = 0;
    Widget reveal(Widget child) =>
        Reveal(delay: Motion.stagger * (step++), child: child);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double content = c.maxWidth - StoryDetailView.padding.horizontal;
        bool columns(int n) =>
            expanded && StoryDetailView.columnsFit(context, content, n);

        return SingleChildScrollView(
          padding: StoryDetailView.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              reveal(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        story.title,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StoryMeta(story: story),
                    const SizedBox(height: 10),
                    // Two slim bars: the spread at a glance; the full
                    // "Who covered it" picture (the one spoken node) sits
                    // below the comparison, so these stay silent.
                    ExcludeSemantics(
                      child: CoverageIndicator(
                        story: story,
                        digest: digest,
                        minimal: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              reveal(
                InBriefCard(story: story, digest: digest, onJump: _jumpOnAxis),
              ),
              const SizedBox(height: 24),
              if (story.analysisUnavailable)
                reveal(
                  const Section(
                    title: Copy.analysisUnavailableTitle,
                    children: <Widget>[
                      NoneFound(
                        key: StoryDetailView.analysisUnavailableKey,
                        text: Copy.analysisUnavailable,
                      ),
                    ],
                  ),
                )
              else ...<Widget>[
                reveal(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SegmentedButton<PerspectiveAxis>(
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<PerspectiveAxis>>[
                          ButtonSegment<PerspectiveAxis>(
                            value: PerspectiveAxis.lean,
                            label: Text(Copy.axisLean),
                          ),
                          ButtonSegment<PerspectiveAxis>(
                            value: PerspectiveAxis.bloc,
                            label: Text(Copy.axisBloc),
                          ),
                        ],
                        selected: <PerspectiveAxis>{axis},
                        onSelectionChanged: (Set<PerspectiveAxis> s) =>
                            controller.setAxis(s.first),
                      ),
                      const SizedBox(height: 10),
                      _JumpBar(
                        items: axis == PerspectiveAxis.lean
                            ? _leanJumps()
                            : _blocJumps(),
                        onJump: _jumpTo,
                      ),
                    ],
                  ),
                ),
                reveal(
                  AxisSwitcher(
                    forward: forward,
                    child: Column(
                      key: ValueKey<PerspectiveAxis>(axis),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: axis == PerspectiveAxis.lean
                          ? _leanSections(context, columns)
                          : _blocSections(context, columns),
                    ),
                  ),
                ),
              ],
              reveal(
                Section(
                  title: Copy.whoCovered,
                  subtitle: Copy.whoCoveredNote,
                  children: <Widget>[
                    CoverageIndicator(
                      story: story,
                      digest: digest,
                      compact: false,
                      onSideTap: (String side, List<Outlet> outlets) {
                        final Set<String> ids = <String>{
                          for (final Outlet o in outlets) o.id,
                        };
                        showSourcesSheet(
                          context,
                          story: story,
                          digest: digest,
                          ids: <String>[
                            for (final Article a in story.articles)
                              if (ids.contains(a.outletId)) a.id,
                          ],
                        );
                      },
                    ),
                    if (unrated > 0) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        Copy.unratedNote(unrated),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              reveal(
                Section(
                  key: _anchor(_Jump.sources, null),
                  highlighted: _flash == _anchorId(_Jump.sources, null),
                  title: '${Copy.sources} (${story.articles.length})',
                  children: <Widget>[SourcesList(story: story, digest: digest)],
                ),
              ),
              const SizedBox(height: 8),
              ReportStoryTile(title: story.title, date: digest.date),
            ],
          ),
        );
      },
    );
  }

  List<_Jump> _leanJumps() => <_Jump>[
    const _Jump(_Jump.headlines, Copy.jumpHeadlines),
    const _Jump(_Jump.emphasis, Copy.jumpEmphasis),
    _Jump(_Jump.agreed, Copy.jumpAgreed, story.agreedFacts.length),
    _Jump(_Jump.omissions, Copy.jumpOmissions, story.omissions.length),
    _Jump(_Jump.contested, Copy.jumpContested, story.contestedClaims.length),
    _Jump(_Jump.opinion, Copy.jumpOpinion, story.opinion.length),
    _Jump(_Jump.sources, Copy.jumpSources, story.articles.length),
  ];

  List<_Jump> _blocJumps() => <_Jump>[
    const _Jump(_Jump.headlines, Copy.jumpHeadlines),
    const _Jump(_Jump.emphasis, Copy.jumpEmphasis),
    _Jump(
      _Jump.contradictions,
      Copy.jumpContradictions,
      story.contradictions.length,
    ),
    _Jump(_Jump.sources, Copy.jumpSources, story.articles.length),
  ];

  /// Every side of the axis, as columns when they fit, else stacked with a
  /// rail each. [cell] builds one side's content.
  Widget _sides<G>({
    required List<G> sides,
    required bool columns,
    required Color Function(G) color,
    required String Function(G) label,
    required int Function(G) count,
    required String Function(G) wire,
    required Widget Function(G) cell,
  }) {
    if (sides.isEmpty) return const NoneFound();
    if (columns) {
      return PerspectiveColumns(
        columns: <PerspectiveColumn>[
          for (final G g in sides)
            PerspectiveColumn(
              key: PerspectiveColumns.keyFor(wire(g)),
              color: color(g),
              label: label(g),
              count: count(g),
              child: cell(g),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < sides.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == sides.length - 1 ? 0 : 18),
            child: SideBlock(
              color: color(sides[i]),
              label: label(sides[i]),
              count: count(sides[i]),
              child: cell(sides[i]),
            ),
          ),
      ],
    );
  }

  List<Widget> _leanSections(BuildContext context, bool Function(int) columns) {
    final List<Lean> leans = story.leansPresent;
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final bool asColumns = columns(leans.length);

    Widget sides(Widget Function(Framing<Lean>) cell) => _sides<Lean>(
      sides: leans,
      columns: asColumns,
      color: colors.forLean,
      label: Copy.leanGroup,
      count: story.coverage.forLean,
      wire: (Lean l) => l.wire,
      cell: (Lean l) => cell(story.framingFor(l)!),
    );

    final Map<Lean, List<Omission>> omissionsByLean = <Lean, List<Omission>>{
      for (final Lean l in Lean.values)
        if (story.omissions.any((Omission o) => o.lean == l))
          l: story.omissions.where((Omission o) => o.lean == l).toList(),
    };

    return <Widget>[
      Section(
        key: _anchor(_Jump.headlines, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.headlines, PerspectiveAxis.lean),
        title: Copy.headlines,
        children: <Widget>[
          sides(
            (Framing<Lean> f) => QuoteList(
              quotes: f.headlineQuotes,
              story: story,
              digest: digest,
            ),
          ),
        ],
      ),
      Section(
        key: _anchor(_Jump.emphasis, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.emphasis, PerspectiveAxis.lean),
        title: Copy.emphasis,
        children: <Widget>[
          sides(
            (Framing<Lean> f) =>
                PointList(points: f.emphasis, story: story, digest: digest),
          ),
        ],
      ),
      Section(
        key: _anchor(_Jump.agreed, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.agreed, PerspectiveAxis.lean),
        title: Copy.agreed,
        children: <Widget>[
          PointList(points: story.agreedFacts, story: story, digest: digest),
        ],
      ),
      Section(
        key: _anchor(_Jump.omissions, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.omissions, PerspectiveAxis.lean),
        title: Copy.omissions,
        children: <Widget>[
          if (omissionsByLean.isEmpty) const NoneFound(),
          for (final MapEntry<Lean, List<Omission>> e
              in omissionsByLean.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: SideBlock(
                color: colors.forLean(e.key),
                label: Copy.omissionHeading(e.key),
                child: PointList(
                  points: <SourcedPoint>[
                    for (final Omission o in e.value) o.point,
                  ],
                  story: story,
                  digest: digest,
                ),
              ),
            ),
        ],
      ),
      Section(
        key: _anchor(_Jump.contested, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.contested, PerspectiveAxis.lean),
        title: Copy.contested,
        children: <Widget>[
          if (story.contestedClaims.isEmpty) const NoneFound(),
          for (final ContestedClaim c in story.contestedClaims)
            ContestedClaimCard(claim: c, story: story, digest: digest),
        ],
      ),
      Section(
        key: _anchor(_Jump.opinion, PerspectiveAxis.lean),
        highlighted: _flash == _anchorId(_Jump.opinion, PerspectiveAxis.lean),
        title: Copy.opinion,
        subtitle: Copy.opinionNote,
        tinted: true,
        children: <Widget>[
          PointList(points: story.opinion, story: story, digest: digest),
        ],
      ),
    ];
  }

  List<Widget> _blocSections(BuildContext context, bool Function(int) columns) {
    final List<Bloc> blocs = story.blocsPresent;
    final PerspectiveColors colors = PerspectiveColors.of(context);
    final bool asColumns = columns(blocs.length);

    Widget sides(Widget Function(Framing<Bloc>) cell) => _sides<Bloc>(
      sides: blocs,
      columns: asColumns,
      color: colors.forBloc,
      label: Copy.blocGroup,
      count: story.coverage.forBloc,
      wire: (Bloc b) => b.wire,
      cell: (Bloc b) => cell(story.framingForBloc(b)!),
    );

    return <Widget>[
      Section(
        key: _anchor(_Jump.headlines, PerspectiveAxis.bloc),
        highlighted: _flash == _anchorId(_Jump.headlines, PerspectiveAxis.bloc),
        title: Copy.headlines,
        children: <Widget>[
          sides(
            (Framing<Bloc> f) => QuoteList(
              quotes: f.headlineQuotes,
              story: story,
              digest: digest,
            ),
          ),
        ],
      ),
      Section(
        key: _anchor(_Jump.emphasis, PerspectiveAxis.bloc),
        highlighted: _flash == _anchorId(_Jump.emphasis, PerspectiveAxis.bloc),
        title: Copy.emphasis,
        children: <Widget>[
          sides(
            (Framing<Bloc> f) =>
                PointList(points: f.emphasis, story: story, digest: digest),
          ),
        ],
      ),
      Section(
        key: _anchor(_Jump.contradictions, PerspectiveAxis.bloc),
        highlighted:
            _flash == _anchorId(_Jump.contradictions, PerspectiveAxis.bloc),
        title: Copy.contradictions,
        subtitle: Copy.contradictionsNote,
        children: <Widget>[
          // Spans the full width, i.e. both bloc columns, in column mode.
          if (story.contradictions.isEmpty)
            const NoneFound(
              key: StoryDetailView.noContradictionsKey,
              text: Copy.noContradictions,
            ),
          for (final Contradiction c in story.contradictions)
            ContradictionCard(
              contradiction: c,
              story: story,
              digest: digest,
              // Contradiction rows always need a West and an East column.
              sideBySide: columns(2),
            ),
        ],
      ),
    ];
  }
}

/// One icon per section, shared by the section headings and the jump bar.
abstract final class SectionIcons {
  static const IconData headlines = Icons.format_quote_outlined;
  static const IconData emphasis = Icons.highlight_outlined;
  static const IconData agreed = Icons.handshake_outlined;
  static const IconData omissions = Icons.visibility_off_outlined;
  static const IconData contested = Icons.compare_arrows;
  static const IconData opinion = Icons.chat_bubble_outline;
  static const IconData contradictions = Icons.swap_horiz;
  static const IconData sources = Icons.newspaper_outlined;

  static IconData forSection(String id) => switch (id) {
    _Jump.headlines => headlines,
    _Jump.emphasis => emphasis,
    _Jump.agreed => agreed,
    _Jump.omissions => omissions,
    _Jump.contested => contested,
    _Jump.opinion => opinion,
    _Jump.contradictions => contradictions,
    _ => sources,
  };
}

/// A jump-bar entry: section id, short label, optional count.
class _Jump {
  const _Jump(this.id, this.label, [this.count]);
  final String id;
  final String label;
  final int? count;

  static const String headlines = 'headlines';
  static const String emphasis = 'emphasis';
  static const String agreed = 'agreed';
  static const String omissions = 'omissions';
  static const String contested = 'contested';
  static const String opinion = 'opinion';
  static const String contradictions = 'contradictions';
  static const String sources = 'sources';
}

/// "On this page": one chip per section, with its count, scrolling the page
/// to that section. Horizontal, so it never grows the page.
class _JumpBar extends StatelessWidget {
  const _JumpBar({required this.items, required this.onJump});

  final List<_Jump> items;
  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      container: true,
      label: Copy.onThisPage,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 6),
              Semantics(
                button: true,
                label: items[i].count == null
                    ? '${items[i].label}. Jumps to the section.'
                    : '${items[i].label}, ${items[i].count}. '
                          'Jumps to the section.',
                excludeSemantics: true,
                onTap: () => onJump(items[i].id),
                child: ActionChip(
                  key: ValueKey<String>('jump-${items[i].id}'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(items[i].label),
                      if (items[i].count case final int n) ...<Widget>[
                        const SizedBox(width: 5),
                        Text(
                          '$n',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onPressed: () => onJump(items[i].id),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Equal-width perspective columns that scroll with the page. Each column
/// is its own semantics container so a screen reader announces its header
/// and reads it top to bottom before moving to the next.
class PerspectiveColumns extends StatelessWidget {
  const PerspectiveColumns({super.key, required this.columns});

  final List<PerspectiveColumn> columns;

  static Key keyFor(String wire) =>
      ValueKey<String>('perspective-column-$wire');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < columns.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: StoryDetailView.columnGap),
          Expanded(child: columns[i]),
        ],
      ],
    );
  }
}

/// One side as a column: a [SideBlock] with its rail along the top.
class PerspectiveColumn extends StatelessWidget {
  const PerspectiveColumn({
    super.key,
    required this.color,
    required this.label,
    required this.child,
    this.count,
  });

  final Color color;
  final String label;
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) => SideBlock(
    color: color,
    label: label,
    count: count,
    rail: RailSide.top,
    child: child,
  );
}
