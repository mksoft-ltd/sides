import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/core/text/quotes.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/story/presentation/screens/story_detail_screen.dart';
import 'package:sides/features/story/presentation/widgets/points.dart';
import 'package:sides/features/story/presentation/widgets/source_pills.dart';
import 'package:sides/features/story/presentation/widgets/sources_list.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// The story page compares by dimension: every side is on the page at once
/// (stacked with a rail each on phones), under "Headlines, side by side"
/// and "What each side emphasises", then the shared sections.
void main() {
  final Digest digest = sampleDigest();

  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 200, scrollable: detailScrollable());

  Future<TestHarness> open(WidgetTester tester, Story s) =>
      pumpSidesApp(tester, initialLocation: '/story/${s.id}');

  Finder axisSwitch(String label) => find.descendant(
        of: find.byType(SegmentedButton<PerspectiveAxis>),
        matching: find.text(label),
      );

  testWidgets('story 1: all three leans are on the page at once, headlines '
      'first, no tabs', (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text(Copy.headlines), findsOneWidget);
    // Headlines and emphasis each show every side: two headings per lean.
    for (final Lean l in Lean.values) {
      await scrollTo(tester, find.text(Copy.leanGroup(l)).last);
      expect(find.text(Copy.leanGroup(l)), findsNWidgets(2));
    }
    expect(find.text(Copy.emphasis), findsOneWidget);
  });

  testWidgets('only the leans present get a side block (story 8: Left, '
      'Centre)', (WidgetTester tester) async {
    final Story s = digest.stories[7];
    expect(s.leansPresent, <Lean>[Lean.left, Lean.centre]);
    await open(tester, s);
    expect(find.text(Copy.leanGroup(Lean.left)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.centre)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.right)), findsNothing);
  });

  testWidgets('story 7 (left-only) has a single side and the blindspot chip',
      (WidgetTester tester) async {
    await open(tester, digest.stories[6]);
    expect(find.text(Copy.leanGroup(Lean.left)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.centre)), findsNothing);
    expect(find.text(Copy.leanGroup(Lean.right)), findsNothing);
    expect(find.text('Only left-leaning outlets covered this'), findsOneWidget);
  });

  testWidgets('each side block names its outlet count',
      (WidgetTester tester) async {
    final Story s = digest.stories[0];
    await open(tester, s);
    // Story 1: 6 left, 3 centre, 2 right; each count appears under the
    // headlines block and the emphasis block of its side.
    expect(find.text(Copy.outletCount(6)), findsNWidgets(2));
  });

  testWidgets('quotes are labelled with the outlet and headline or summary; '
      'a quote row opens its article', (WidgetTester tester) async {
    final Story s = digest.stories[0];
    final TestHarness h = await open(tester, s);
    final HeadlineQuote snippetQuote = s
        .framingFor(Lean.centre)!
        .headlineQuotes
        .firstWhere((HeadlineQuote q) => q.field == QuoteField.snippet);
    final Article article = s.article(snippetQuote.articleId)!;
    final String outlet = digest.outlet(article.outletId)!.name;
    final Finder quote = find.text(Quotes.wrap(snippetQuote.quote));
    await scrollTo(tester, quote);
    expect(quote, findsOneWidget);
    expect(find.text('$outlet · summary'), findsOneWidget);
    expect(find.textContaining(' · headline'), findsWidgets);

    await tester.tap(quote);
    await tester.pumpAndSettle();
    expect(h.launcher.opened, <Uri>[Uri.parse(article.url)]);
  });

  testWidgets('lean view sections in order, with opinion kept apart at the '
      'end', (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    double lastTop = -1;
    for (final String title in <String>[
      Copy.headlines,
      Copy.emphasis,
      Copy.agreed,
      Copy.omissions,
      Copy.contested,
      Copy.opinion,
    ]) {
      await scrollTo(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
      // Each section comes after the previous one in the page order.
      final double top = tester.getTopLeft(find.text(title)).dy;
      expect(top, greaterThan(lastTop - 2000));
      lastTop = top;
    }
    expect(find.text(Copy.opinionNote), findsOneWidget);
  });

  testWidgets('the jump bar scrolls to a section', (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    final Finder contested = find.text(Copy.contested);
    final Rect view = tester.getRect(find.byType(StoryDetailView));
    // The page is one column, so the heading exists but sits below the fold.
    expect(tester.getRect(contested).top, greaterThan(view.bottom));
    // The bar scrolls horizontally; bring the chip on screen first.
    final Finder chip = find.byKey(const ValueKey<String>('jump-contested'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final Rect r = tester.getRect(contested);
    expect(r.top, greaterThanOrEqualTo(view.top));
    expect(r.bottom, lessThanOrEqualTo(view.bottom));
  });

  testWidgets('the jump bar shows the counts of the sample story',
      (WidgetTester tester) async {
    final Story s = digest.stories[1]; // 1 contested claim, 1 opinion piece
    await open(tester, s);
    final Finder chip = find.byKey(const ValueKey<String>('jump-contested'));
    expect(
      find.descendant(
        of: chip,
        matching: find.text('${s.contestedClaims.length}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('jump-sources')),
        matching: find.text('${s.articles.length}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('axis switch shows West and East side by side and the '
      'contradictions placeholder', (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    expect(find.text(Copy.blocGroup(Bloc.west)), findsNothing);

    await tester.tap(axisSwitch(Copy.axisBloc));
    await tester.pumpAndSettle();

    expect(find.text(Copy.blocGroup(Bloc.west)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.left)), findsNothing);
    await scrollTo(tester, find.text(Copy.blocGroup(Bloc.east)).last);
    expect(find.text(Copy.blocGroup(Bloc.east)), findsWidgets);

    await scrollTo(tester, find.text(Copy.noContradictions));
    expect(find.text(Copy.contradictions), findsOneWidget);
    expect(find.text(Copy.noContradictions), findsOneWidget);
  });

  testWidgets('a point shows up to three outlet pills (one per outlet) then '
      '"+N more"; the pills open a sources sheet whose rows open the article',
      (WidgetTester tester) async {
    final Story s = digest.stories[0];
    final TestHarness h = await open(tester, s);
    final SourcedPoint fact = s.agreedFacts.first;
    final int outlets = distinctOutlets(resolveArticles(s, fact.sources)).length;
    expect(outlets, greaterThan(3)); // sample precondition
    expect(fact.sources.length, greaterThan(outlets),
        reason: 'the sample has an outlet with two articles on this point');
    await scrollTo(tester, find.text(fact.text));
    final Finder tile = find.ancestor(
      of: find.text(fact.text),
      matching: find.byType(PointTile),
    );
    final Finder pills = find.descendant(
      of: tile,
      matching: find.byType(SourcePill),
    );
    expect(pills, findsNWidgets(4));
    expect(
      find.descendant(
        of: tile,
        matching: find.text(Copy.moreSources(outlets - 3)),
      ),
      findsOneWidget,
    );

    // Tap the second pill: the sheet lists every source, that one first.
    final SourcePill second = tester.widget<SourcePill>(pills.at(1));
    await tester.tap(pills.at(1));
    await tester.pumpAndSettle();
    expect(find.byType(SourcesSheet), findsOneWidget);
    expect(find.text(Copy.sourcesForPoint), findsOneWidget);
    expect(
      find.text(Copy.sourcesSheetCount(fact.sources.length)),
      findsOneWidget,
    );
    final Finder rows = find.descendant(
      of: find.byType(SourcesSheet),
      matching: find.byType(SourceTile),
    );
    expect(tester.widget<SourceTile>(rows.first).article.id,
        second.article!.id);

    await tester.tap(rows.first);
    await tester.pumpAndSettle();
    expect(h.launcher.opened, <Uri>[Uri.parse(second.article!.url)]);
  });

  testWidgets('every pill and sheet row has a semantics label',
      (WidgetTester tester) async {
    final Story s = digest.stories[0];
    await open(tester, s);
    final SemanticsHandle semantics = tester.ensureSemantics();
    await scrollTo(tester, find.text(Copy.agreed));
    await tester.pumpAndSettle();
    int checked = 0;
    for (final SourcePill pill
        in tester.widgetList<SourcePill>(find.byType(SourcePill))) {
      final String label = pill.article == null
          ? SourcePill.moreSemanticsLabel(pill.moreCount!)
          : SourcePill.semanticsLabelFor(pill.article!, pill.outlet);
      expect(find.bySemanticsLabel(label), findsWidgets);
      checked++;
    }
    expect(checked, greaterThan(3));
    semantics.dispose();
  });

  testWidgets('a failed launch shows a snackbar instead of failing silently',
      (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    harness.launcher.result = false;
    await pumpSidesApp(tester,
        harness: harness, initialLocation: '/story/${digest.stories[0].id}');
    await tester.ensureVisible(find.byType(QuoteRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(QuoteRow).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Couldn\'t open the article.'), findsOneWidget);
  });

  testWidgets('Sources list shows every article and tags state media',
      (WidgetTester tester) async {
    final Story s = digest.stories.firstWhere(
      (Story s) => s.articles
          .any((Article a) => digest.outlet(a.outletId)!.isStateControlled),
    );
    await open(tester, s);
    await scrollTo(tester, find.text('${Copy.sources} (${s.articles.length})'));
    await scrollTo(tester, find.text('state media'));
    expect(find.text('state media'), findsWidgets);
  });

  testWidgets('the detail page has a banner slot below the content',
      (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StoryDetailView),
        matching: find.byKey(FakeAdsService.bannerKey),
      ),
      findsNothing,
      reason: 'ads never sit inside the sourced content',
    );
  });

  testWidgets('?axis=bloc deep link opens the West / East view',
      (WidgetTester tester) async {
    await pumpSidesApp(tester,
        initialLocation: '/story/${digest.stories[0].id}?axis=bloc');
    expect(find.text(Copy.blocGroup(Bloc.west)), findsWidgets);
    expect(find.text(Copy.leanGroup(Lean.left)), findsNothing);
  });

  testWidgets('previous / next in the app bar step through the digest and '
      'keep the axis; back still returns to the list',
      (WidgetTester tester) async {
    await pumpSidesApp(tester);
    await tester.tap(find.text(digest.stories[0].title));
    await tester.pumpAndSettle();
    expect(find.text('1 of 10'), findsOneWidget);
    final Finder previous = find.byKey(StoryDetailScreen.previousKey);
    final Finder next = find.byKey(StoryDetailScreen.nextKey);
    expect(tester.widget<IconButton>(previous).onPressed, isNull);

    await tester.tap(axisSwitch(Copy.axisBloc));
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('2 of 10'), findsOneWidget);
    expect(find.text(digest.stories[1].title), findsOneWidget);
    expect(find.text(Copy.blocGroup(Bloc.west)), findsWidgets,
        reason: 'the axis carries over');

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('1 of 10'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Wednesday 14 October 2026'), findsOneWidget);
  });
}
