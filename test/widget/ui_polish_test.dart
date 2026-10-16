import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/theme/app_theme.dart';
import 'package:sides/features/digest/presentation/widgets/story_card.dart';
import 'package:sides/features/story/presentation/widgets/points.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';
import 'package:sides/shared/widgets/sides_mark.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// BRAND.md "Recommended UI polish", items 1, 2, 3, 5 and 6. Item 4 (native
/// launch screens) is checked by building both platforms, not here.
void main() {
  final digest = sampleDigest();

  Finder appBarText(String s) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(s));

  group('1. nested quotes', () {
    testWidgets('an inner straight quote renders as a single curly quote',
        (WidgetTester tester) async {
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      // Fox News, story 1: `identified at a "very early stage."`
      const String expected = '“identified at a ‘very early stage.’”';
      await tester.scrollUntilVisible(
        find.text(expected),
        300,
        scrollable: find
            .descendant(
              of: find.byType(StoryDetailView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(expected), findsOneWidget);
      expect(find.textContaining('"'), findsNothing);
    });
  });

  group('2. detail title is a position', () {
    testWidgets('"1 of 10", spoken as "Story 1 of 10"',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      expect(appBarText('1 of ${digest.stories.length}'), findsOneWidget);
      expect(find.bySemanticsLabel('Story 1 of 10'), findsOneWidget);
      expect(appBarText('Story 1'), findsNothing);
      semantics.dispose();
    });
  });

  group('3. wordmark', () {
    for (final (String name, Size size) in <(String, Size)>[
      ('phone', phoneSize),
      ('tablet master-detail', const Size(834, 1194)),
    ]) {
      testWidgets('$name list app bar: newspaper mark then "Sides"',
          (WidgetTester tester) async {
        await pumpSidesApp(tester, size: size);
        final Finder mark = find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(SidesMark),
        );
        expect(mark, findsOneWidget);
        expect(tester.getSize(mark), const Size(20, 20));
        expect(
          tester.getCenter(mark).dx,
          lessThan(tester.getCenter(appBarText('Sides')).dx),
        );
      });
    }

    testWidgets('the mark paints the lean colours of the active theme',
        (WidgetTester tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        await tester.pumpWidget(
          MaterialApp(theme: theme, home: const Center(child: SidesMark())),
        );
        await tester.pumpAndSettle(); // let the theme animation finish
        final SidesMarkPainter p = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(SidesMark),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter! as SidesMarkPainter;
        final PerspectiveColors c = theme.extension<PerspectiveColors>()!;
        expect(<Color>[p.left, p.page, p.right], <Color>[
          c.left,
          c.centre,
          c.right,
        ]);
      }
    });

    test('geometry: front page between two fanned sheets, furniture inside',
        () {
      const Rect page = SidesMarkPainter.pageRect;
      final Rect design = Offset.zero & SidesMarkPainter.designSize;
      // The sheets sit either side of the page, never under it, so the page
      // furniture (holes) shows the surface and not a sheet colour.
      for (final Offset p in SidesMarkPainter.leftSheet) {
        expect(p.dx, lessThan(page.left));
        expect(design.contains(p), isTrue);
      }
      for (final Offset p in SidesMarkPainter.rightSheet) {
        expect(p.dx, greaterThan(page.right));
        expect(p.dx, lessThanOrEqualTo(design.right));
      }
      final List<Rect> holes = SidesMarkPainter.pageHoles();
      // Headline + photo + 2 lines beside it + 3 rows of 3 columns.
      expect(holes, hasLength(13));
      final Rect inner = page.deflate(30);
      for (int i = 0; i < holes.length; i++) {
        expect(inner.contains(holes[i].topLeft), isTrue, reason: 'hole $i');
        expect(inner.contains(holes[i].bottomRight), isTrue,
            reason: 'hole $i');
        for (int j = i + 1; j < holes.length; j++) {
          // Even-odd fill: overlapping holes would re-fill their overlap.
          expect(holes[i].overlaps(holes[j]), isFalse, reason: 'holes $i/$j');
        }
      }
      // Thin furniture stays about 0.9 dp tall at the 20 dp app-bar size.
      const double dp = 20 / 760;
      for (final Rect h in holes) {
        expect(h.height * dp, greaterThan(0.85));
      }
    });
  });

  group('5. quote rows carry no duplicate chip', () {
    testWidgets('a headline quote names its outlet once and opens the '
        'article itself', (WidgetTester tester) async {
      final TestHarness h = await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      final Finder row = find.byType(QuoteRow).first;
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byType(StoryDetailView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final QuoteRow quote = tester.widget<QuoteRow>(row);
      final String outlet = digest
          .outlet(digest.stories.first.article(quote.quote.articleId)!.outletId)!
          .name;
      expect(
        find.descendant(of: row, matching: find.textContaining(outlet)),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(h.launcher.opened, hasLength(1));
    });
  });

  group('6. rank badge', () {
    testWidgets('uses the neutral surfaceContainerHighest, not primary',
        (WidgetTester tester) async {
      await pumpSidesApp(tester);
      final BuildContext ctx = tester.element(find.byType(StoryCard).first);
      final ColorScheme cs = Theme.of(ctx).colorScheme;
      final Finder badge = find.ancestor(
        of: find.descendant(
          of: find.byType(StoryCard).first,
          matching: find.text('1'),
        ),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(badge, findsOneWidget);
      final BoxDecoration d =
          tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect(d.color, cs.surfaceContainerHighest);
      final Text rank = tester.widget<Text>(
        find.descendant(of: badge, matching: find.text('1')),
      );
      expect(rank.style?.color, cs.onSurface);
    });
  });
}
