import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/theme/app_theme.dart';
import 'package:sides/features/digest/presentation/widgets/story_card.dart';
import 'package:sides/features/story/presentation/widgets/source_chips.dart';
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
      await tester.tap(find.widgetWithText(Tab, 'Right'));
      await tester.pumpAndSettle();
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
      testWidgets('$name list app bar: cube mark then "Sides"',
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
        expect(<Color>[p.left, p.top, p.right], <Color>[
          c.left,
          c.centre,
          c.right,
        ]);
      }
    });

    test('geometry matches build_icon.py: three faces, Y seam of 18/340', () {
      final List<List<Offset>> f = SidesMarkPainter.unitFaces();
      expect(f, hasLength(3));
      // The top face's shared corner sits GAP above the centre.
      expect(f[0][2].dy, closeTo(-18 / 340, 1e-9));
      expect(f[0][2].dx, closeTo(0, 1e-9));
    });
  });

  group('5. source chip lines', () {
    int chipMaxLines(WidgetTester tester) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(SourceChip).first,
                matching: find.byType(Text),
              )
              .first,
        )
        .maxLines!;

    testWidgets('2 lines on a phone', (WidgetTester tester) async {
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      await tester.scrollUntilVisible(
        find.byType(SourceChip).first,
        200,
        scrollable: find
            .descendant(
              of: find.byType(StoryDetailView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(chipMaxLines(tester), 2);
    });

    for (final Size size in <Size>[
      const Size(744, 1133),
      const Size(1366, 1024),
    ]) {
      testWidgets('3 lines at ${size.width.toInt()} dp',
          (WidgetTester tester) async {
        await pumpSidesApp(
          tester,
          size: size,
          initialLocation: '/story/${digest.stories.first.id}',
        );
        await tester.scrollUntilVisible(
          find.byType(SourceChip).first,
          200,
          scrollable: find
              .descendant(
                of: find.byType(StoryDetailView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(chipMaxLines(tester), 3);
      });
    }
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
