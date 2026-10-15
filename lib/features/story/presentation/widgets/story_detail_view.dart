import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/copy.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/blindspot_chips.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/report_story_tile.dart';
import '../../../../shared/widgets/section.dart';
import '../../../digest/domain/digest.dart';
import '../providers/story_view_controller.dart';
import 'points.dart';
import 'sources_list.dart';

export '../providers/story_view_controller.dart' show PerspectiveAxis;

/// The whole story page without a scaffold: the phone page and the tablet
/// detail pane both host it. The axis and tab choice live in
/// [storyViewProvider], so swapping layouts keeps the reader's place.
///
/// Perspectives render as tabs, or — at [LayoutSize.expanded] when every
/// column still gets [minColumnWidth] at the current text scale — as
/// side-by-side columns (see [columnsFit]).
class StoryDetailView extends ConsumerWidget {
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
  /// text, so at 200% a column needs 560 dp or the view falls back to tabs.
  static const double minColumnWidth = 280;
  static const double columnGap = ContradictionCard.columnGap;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(16, 8, 16, 32);

  /// Whether [count] columns fit side by side in [width] (the content width,
  /// padding already removed) at this context's text scale.
  static bool columnsFit(BuildContext context, double width, int count) {
    if (count < 1) return false;
    final double min = MediaQuery.textScalerOf(context).scale(minColumnWidth);
    return (width - columnGap * (count - 1)) / count >= min;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StoryViewState view = ref.watch(storyViewProvider(story.id));
    final StoryViewController controller = ref.read(
      storyViewProvider(story.id).notifier,
    );
    final PerspectiveAxis axis = view.axisOr(initialAxis);
    final bool expanded = LayoutSize.of(context) == LayoutSize.expanded;
    final ThemeData theme = Theme.of(context);
    final int unrated = story.outletCount - story.coverage.leanTotal;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double content = c.maxWidth - padding.horizontal;
        bool columns(int n) => expanded && columnsFit(context, content, n);

        return ListView(
          padding: padding,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(story.title, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 6),
            Text(
              'Covered by ${Copy.outletCount(story.outletCount)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            CoverageIndicator(coverage: story.coverage, compact: false),
            BlindspotChips(blindspot: story.blindspot),
            if (unrated > 0) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                Copy.unratedNote(unrated),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (story.analysisUnavailable)
              const Section(
                title: Copy.analysisUnavailableTitle,
                children: <Widget>[
                  NoneFound(
                    key: StoryDetailView.analysisUnavailableKey,
                    text: Copy.analysisUnavailable,
                  ),
                ],
              )
            else ...<Widget>[
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
            const SizedBox(height: 8),
            if (axis == PerspectiveAxis.lean)
              ..._leanView(
                context,
                view,
                controller,
                columns: columns(story.leansPresent.length),
              )
            else
              ..._blocView(
                context,
                view,
                controller,
                // Contradiction rows always need a West and an East column.
                columns: columns(2),
              ),
            ],
            Section(
              title: '${Copy.sources} (${story.articles.length})',
              children: <Widget>[SourcesList(story: story, digest: digest)],
            ),
            ReportStoryTile(title: story.title, date: digest.date),
          ],
        );
      },
    );
  }

  List<Widget> _leanView(
    BuildContext context,
    StoryViewState view,
    StoryViewController controller, {
    required bool columns,
  }) {
    final List<Lean> leans = story.leansPresent;
    final PerspectiveColors colors = PerspectiveColors.of(context);

    FramingPanel panel(Framing<Lean> f) => FramingPanel(
      groupLabel: Copy.leanGroup(f.group),
      quotes: f.headlineQuotes,
      emphasis: f.emphasis,
      story: story,
      digest: digest,
    );

    final List<Widget> perspectives;
    if (columns) {
      perspectives = <Widget>[
        const SizedBox(height: 16),
        PerspectiveColumns(
          columns: <PerspectiveColumn>[
            for (final Lean l in leans)
              PerspectiveColumn(
                key: PerspectiveColumns.keyFor(l.wire),
                color: colors.forLean(l),
                child: panel(story.framingFor(l)!),
              ),
          ],
        ),
      ];
    } else {
      final int index = view.leanTab.clamp(
        0,
        leans.isEmpty ? 0 : leans.length - 1,
      );
      final Framing<Lean>? framing = leans.isEmpty
          ? null
          : story.framingFor(leans[index]);
      perspectives = <Widget>[
        if (leans.isNotEmpty)
          _Tabs(
            key: ValueKey<String>('lean-${story.id}'),
            labels: <String>[for (final Lean l in leans) l.label],
            index: index,
            onTap: controller.setLeanTab,
          ),
        const SizedBox(height: 16),
        if (framing != null) panel(framing) else const NoneFound(),
      ];
    }

    final Map<Lean, List<Omission>> omissionsByLean = <Lean, List<Omission>>{
      for (final Lean l in Lean.values)
        if (story.omissions.any((Omission o) => o.lean == l))
          l: story.omissions.where((Omission o) => o.lean == l).toList(),
    };

    return <Widget>[
      ...perspectives,
      Section(
        title: Copy.agreed,
        children: <Widget>[
          if (story.agreedFacts.isEmpty) const NoneFound(),
          for (final SourcedPoint p in story.agreedFacts)
            SourcedPointTile(point: p, story: story, digest: digest),
        ],
      ),
      Section(
        title: Copy.omissions,
        children: <Widget>[
          if (omissionsByLean.isEmpty) const NoneFound(),
          for (final MapEntry<Lean, List<Omission>> e
              in omissionsByLean.entries) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                Copy.omissionHeading(e.key),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final Omission o in e.value)
              SourcedPointTile(point: o.point, story: story, digest: digest),
          ],
        ],
      ),
      Section(
        title: Copy.contested,
        children: <Widget>[
          if (story.contestedClaims.isEmpty) const NoneFound(),
          for (final ContestedClaim c in story.contestedClaims)
            ContestedClaimCard(claim: c, story: story, digest: digest),
        ],
      ),
      Section(
        title: Copy.opinion,
        subtitle: Copy.opinionNote,
        tinted: true,
        children: <Widget>[
          if (story.opinion.isEmpty) const NoneFound(),
          for (final SourcedPoint p in story.opinion)
            SourcedPointTile(point: p, story: story, digest: digest),
        ],
      ),
    ];
  }

  List<Widget> _blocView(
    BuildContext context,
    StoryViewState view,
    StoryViewController controller, {
    required bool columns,
  }) {
    final List<Bloc> blocs = story.blocsPresent;
    final PerspectiveColors colors = PerspectiveColors.of(context);

    FramingPanel panel(Framing<Bloc> f) => FramingPanel(
      groupLabel: Copy.blocGroup(f.group),
      quotes: f.headlineQuotes,
      emphasis: f.emphasis,
      story: story,
      digest: digest,
    );

    final List<Widget> perspectives;
    if (columns) {
      perspectives = <Widget>[
        const SizedBox(height: 16),
        PerspectiveColumns(
          columns: <PerspectiveColumn>[
            for (final Bloc b in blocs)
              PerspectiveColumn(
                key: PerspectiveColumns.keyFor(b.wire),
                color: colors.forBloc(b),
                child: panel(story.framingForBloc(b)!),
              ),
          ],
        ),
      ];
    } else {
      final int index = view.blocTab.clamp(
        0,
        blocs.isEmpty ? 0 : blocs.length - 1,
      );
      final Framing<Bloc>? framing = blocs.isEmpty
          ? null
          : story.framingForBloc(blocs[index]);
      perspectives = <Widget>[
        if (blocs.isNotEmpty)
          _Tabs(
            key: ValueKey<String>('bloc-${story.id}'),
            labels: <String>[for (final Bloc b in blocs) b.label],
            index: index,
            onTap: controller.setBlocTab,
          ),
        const SizedBox(height: 16),
        if (framing != null) panel(framing) else const NoneFound(),
      ];
    }

    return <Widget>[
      ...perspectives,
      Section(
        title: Copy.contradictions,
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
              sideBySide: columns,
            ),
        ],
      ),
    ];
  }

  static const Key noContradictionsKey = Key('no-contradictions');
  static const Key analysisUnavailableKey = Key('analysis-unavailable');
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

class PerspectiveColumn extends StatelessWidget {
  const PerspectiveColumn({
    super.key,
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: color, width: 4)),
        ),
        child: child,
      ),
    );
  }
}

/// Material tabs that switch the panel below them in place (no
/// TabBarView, which needs a fixed height and fights the outer scroll).
class _Tabs extends StatelessWidget {
  const _Tabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onTap,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: labels.length,
      initialIndex: index,
      child: TabBar(
        onTap: onTap,
        tabs: <Widget>[for (final String l in labels) Tab(text: l)],
      ),
    );
  }
}
