import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/story/presentation/widgets/source_chips.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  final Digest digest = sampleDigest();

  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 300, scrollable: detailScrollable());

  Finder tab(String label) => find.widgetWithText(Tab, label);

  Future<TestHarness> open(WidgetTester tester, Story s) =>
      pumpSidesApp(tester, initialLocation: '/story/${s.id}');

  testWidgets('story 1: all three lean tabs, Left selected first',
      (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    expect(tab('Left'), findsOneWidget);
    expect(tab('Centre'), findsOneWidget);
    expect(tab('Right'), findsOneWidget);
    expect(find.text('Left-leaning outlets'), findsOneWidget);

    await tester.tap(tab('Right'));
    await tester.pumpAndSettle();
    expect(find.text('Right-leaning outlets'), findsOneWidget);
    expect(find.text('Left-leaning outlets'), findsNothing);
  });

  testWidgets('only the leans present get a tab (story 8: Left, Centre)',
      (WidgetTester tester) async {
    final Story s = digest.stories[7];
    expect(s.leansPresent, <Lean>[Lean.left, Lean.centre]);
    await open(tester, s);
    expect(tab('Left'), findsOneWidget);
    expect(tab('Centre'), findsOneWidget);
    expect(tab('Right'), findsNothing);
  });

  testWidgets('story 7 (left-only) has a single Left tab and the chip',
      (WidgetTester tester) async {
    await open(tester, digest.stories[6]);
    expect(tab('Left'), findsOneWidget);
    expect(tab('Centre'), findsNothing);
    expect(tab('Right'), findsNothing);
    expect(find.text('Only left-leaning outlets covered this'), findsOneWidget);
  });

  testWidgets('quotes are labelled headline or snippet with the outlet',
      (WidgetTester tester) async {
    final Story s = digest.stories[0];
    await open(tester, s);
    await tester.tap(tab('Centre'));
    await tester.pumpAndSettle();
    final HeadlineQuote snippetQuote = s
        .framingFor(Lean.centre)!
        .headlineQuotes
        .firstWhere((HeadlineQuote q) => q.field == QuoteField.snippet);
    final String outlet =
        digest.outlet(s.article(snippetQuote.articleId)!.outletId)!.name;
    expect(find.text('“${snippetQuote.quote}”'), findsOneWidget);
    expect(find.text('snippet · $outlet'), findsOneWidget);
    expect(find.textContaining('headline · '), findsWidgets);
  });

  testWidgets('lean view sections, with opinion kept apart at the end',
      (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    for (final String title in <String>[
      Copy.agreed,
      Copy.omissions,
      Copy.contested,
      Copy.opinion,
    ]) {
      await scrollTo(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text(Copy.opinionNote), findsOneWidget);
  });

  testWidgets('axis switch reveals West/East tabs and the contradictions '
      'placeholder', (WidgetTester tester) async {
    await open(tester, digest.stories[0]);
    expect(tab('West'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<PerspectiveAxis>),
      matching: find.text(Copy.axisBloc),
    ));
    await tester.pumpAndSettle();

    expect(tab('West'), findsOneWidget);
    expect(tab('East'), findsOneWidget);
    expect(tab('Left'), findsNothing);
    expect(find.text('Western outlets'), findsOneWidget);
    await tester.tap(tab('East'));
    await tester.pumpAndSettle();
    expect(find.text('Eastern outlets'), findsOneWidget);

    await scrollTo(tester, find.text(Copy.noContradictions));
    expect(find.text(Copy.contradictions), findsOneWidget);
    expect(find.text(Copy.noContradictions), findsOneWidget);
  });

  testWidgets('every source chip has a semantics label; tapping opens the '
      'article via the launcher', (WidgetTester tester) async {
    final Story s = digest.stories[0];
    final TestHarness h = await open(tester, s);
    final SemanticsHandle semantics = tester.ensureSemantics();

    int checked = 0;
    Future<void> checkVisibleChips() async {
      for (final SourceChip chip
          in tester.widgetList<SourceChip>(find.byType(SourceChip))) {
        expect(
          find.bySemanticsLabel(
            SourceChip.semanticsLabelFor(chip.article, chip.outlet),
          ),
          findsWidgets,
        );
        checked++;
      }
    }

    await checkVisibleChips();
    await scrollTo(tester, find.text(Copy.agreed));
    await tester.pumpAndSettle();
    await checkVisibleChips();
    expect(checked, greaterThan(3));

    final SourceChip first =
        tester.widget<SourceChip>(find.byType(SourceChip).first);
    await tester.tap(find.byType(SourceChip).first);
    await tester.pumpAndSettle();
    expect(h.launcher.opened, <Uri>[Uri.parse(first.article.url)]);
    semantics.dispose();
  });

  testWidgets('a failed launch shows a snackbar instead of failing silently',
      (WidgetTester tester) async {
    final TestHarness harness = TestHarness();
    harness.launcher.result = false;
    await pumpSidesApp(tester,
        harness: harness, initialLocation: '/story/${digest.stories[0].id}');
    await tester.ensureVisible(find.byType(SourceChip).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SourceChip).first);
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
    expect(tab('West'), findsOneWidget);
    expect(tab('Left'), findsNothing);
  });
}
