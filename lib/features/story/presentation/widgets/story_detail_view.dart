import 'package:flutter/material.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/blindspot_chips.dart';
import '../../../../shared/widgets/coverage_indicator.dart';
import '../../../../shared/widgets/section.dart';
import '../../../digest/domain/digest.dart';
import 'points.dart';
import 'sources_list.dart';

enum PerspectiveAxis { lean, bloc }

/// The whole story page without a scaffold, so phase 5 can show it in a
/// detail pane next to the list. Phones render it as one scrolling column;
/// the tablet layout will swap [_PerspectivePanel] for side-by-side columns.
class StoryDetailView extends StatefulWidget {
  const StoryDetailView({
    super.key,
    required this.story,
    required this.digest,
  });

  final Story story;
  final Digest digest;

  @override
  State<StoryDetailView> createState() => _StoryDetailViewState();
}

class _StoryDetailViewState extends State<StoryDetailView> {
  PerspectiveAxis _axis = PerspectiveAxis.lean;
  int _leanTab = 0;
  int _blocTab = 0;

  @override
  void didUpdateWidget(StoryDetailView old) {
    super.didUpdateWidget(old);
    if (old.story.id != widget.story.id) {
      _axis = PerspectiveAxis.lean;
      _leanTab = 0;
      _blocTab = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Story story = widget.story;
    final Digest digest = widget.digest;
    final ThemeData theme = Theme.of(context);
    final int unrated = story.outletCount - story.coverage.leanTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(story.title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 6),
        Text(
          'Covered by ${Copy.outletCount(story.outletCount)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        CoverageIndicator(coverage: story.coverage, compact: false),
        BlindspotChips(blindspot: story.blindspot),
        if (unrated > 0) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            Copy.unratedNote(unrated),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 24),
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
          selected: <PerspectiveAxis>{_axis},
          onSelectionChanged: (Set<PerspectiveAxis> s) =>
              setState(() => _axis = s.first),
        ),
        const SizedBox(height: 8),
        if (_axis == PerspectiveAxis.lean)
          ..._leanView(story, digest)
        else
          ..._blocView(story, digest),
        Section(
          title: '${Copy.sources} (${story.articles.length})',
          children: <Widget>[SourcesList(story: story, digest: digest)],
        ),
      ],
    );
  }

  List<Widget> _leanView(Story story, Digest digest) {
    final List<Lean> leans = story.leansPresent;
    final int index = _leanTab.clamp(0, leans.isEmpty ? 0 : leans.length - 1);
    final Lean? lean = leans.isEmpty ? null : leans[index];
    final Framing<Lean>? framing = lean == null ? null : story.framingFor(lean);

    final Map<Lean, List<Omission>> omissionsByLean = <Lean, List<Omission>>{
      for (final Lean l in Lean.values)
        if (story.omissions.any((Omission o) => o.lean == l))
          l: story.omissions.where((Omission o) => o.lean == l).toList(),
    };

    return <Widget>[
      if (leans.isNotEmpty)
        _Tabs(
          key: ValueKey<String>('lean-${story.id}'),
          labels: <String>[for (final Lean l in leans) l.label],
          index: index,
          onTap: (int i) => setState(() => _leanTab = i),
        ),
      const SizedBox(height: 16),
      if (framing != null)
        FramingPanel(
          groupLabel: Copy.leanGroup(framing.group),
          quotes: framing.headlineQuotes,
          emphasis: framing.emphasis,
          story: story,
          digest: digest,
        )
      else
        const NoneFound(),
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

  List<Widget> _blocView(Story story, Digest digest) {
    final List<Bloc> blocs = story.blocsPresent;
    final int index = _blocTab.clamp(0, blocs.isEmpty ? 0 : blocs.length - 1);
    final Bloc? bloc = blocs.isEmpty ? null : blocs[index];
    final Framing<Bloc>? framing =
        bloc == null ? null : story.framingForBloc(bloc);

    return <Widget>[
      if (blocs.isNotEmpty)
        _Tabs(
          key: ValueKey<String>('bloc-${story.id}'),
          labels: <String>[for (final Bloc b in blocs) b.label],
          index: index,
          onTap: (int i) => setState(() => _blocTab = i),
        ),
      const SizedBox(height: 16),
      if (framing != null)
        FramingPanel(
          groupLabel: Copy.blocGroup(framing.group),
          quotes: framing.headlineQuotes,
          emphasis: framing.emphasis,
          story: story,
          digest: digest,
        )
      else
        const NoneFound(),
      Section(
        title: Copy.contradictions,
        children: <Widget>[
          if (story.contradictions.isEmpty)
            const NoneFound(text: Copy.noContradictions),
          for (final Contradiction c in story.contradictions)
            ContradictionCard(contradiction: c, story: story, digest: digest),
        ],
      ),
    ];
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
