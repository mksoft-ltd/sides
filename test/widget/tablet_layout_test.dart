import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/digest/presentation/screens/digest_list_screen.dart';
import 'package:sides/features/digest/presentation/screens/master_detail_screen.dart';
import 'package:sides/features/digest/presentation/widgets/story_card.dart';
import 'package:sides/features/story/presentation/screens/story_detail_screen.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';
import 'package:sides/shared/widgets/section.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Logical (dp) window sizes. pumpSidesApp renders them at 3x physical.
const Size ipad129Portrait = Size(1024, 1366); // 12.9" portrait: medium
const Size ipad129Landscape = Size(1366, 1024); // 12.9" landscape: expanded
const Size ipad11Landscape = Size(1194, 834); // 11" landscape: expanded
const Size ipad102Landscape = Size(1080, 810); // 10.2" landscape: medium
const Size ipad97Portrait = Size(768, 1024); // 9.7" portrait: medium
const Size ipadMiniPortrait = Size(744, 1133); // mini portrait: medium
const Size ipad11Portrait = Size(834, 1194); // 11" portrait: medium
const Size ipadAirPortrait = Size(820, 1180); // Air 11" portrait: medium
const Size justBelowTablet = Size(743, 1000); // compact

void main() {
  final Digest digest = sampleDigest();
  final Story s1 = digest.stories[0];
  final Story s3 = digest.stories[2];
  final Story s5 = digest.stories[4];
  final Story s8 = digest.stories[7]; // Left + Centre only

  final Finder listPane = find.byKey(MasterDetailScreen.listPaneKey);
  final Finder detailPane = find.byKey(MasterDetailScreen.detailPaneKey);
  Finder inDetail(Finder f) => find.descendant(of: detailPane, matching: f);
  Finder inList(Finder f) => find.descendant(of: listPane, matching: f);
  /// Stacked sides (the phone layout inside the pane): a side heading with
  /// a left rail, i.e. no perspective columns.
  Finder stacked(String label) => find.text(label);
  Finder column(String wire) =>
      find.byKey(PerspectiveColumns.keyFor(wire), skipOffstage: true);

  String location(WidgetTester tester) => GoRouter.of(
        tester.element(find.byType(MasterDetailScreen).last),
      ).routerDelegate.currentConfiguration.uri.toString();

  Future<void> resize(WidgetTester tester, Size dp) async {
    tester.view.physicalSize = dp * 3;
    await tester.pumpAndSettle();
  }

  Finder axisSwitch(String label) => find.descendant(
        of: find.byType(SegmentedButton<PerspectiveAxis>),
        matching: find.text(label),
      );

  Future<void> chooseBloc(WidgetTester tester) async {
    await tester.ensureVisible(axisSwitch(Copy.axisBloc));
    await tester.pumpAndSettle();
    await tester.tap(axisSwitch(Copy.axisBloc));
    await tester.pumpAndSettle();
  }

  Finder listScrollable() => inList(find.byType(Scrollable)).first;
  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the list pane to [s] and taps it.
  Future<void> tapStory(WidgetTester tester, Story s) async {
    await tester.scrollUntilVisible(
      inList(find.text(s.title)),
      200,
      scrollable: listScrollable(),
    );
    // scrollUntilVisible stops once the item is built, which happens in the
    // list's cache extent just below the viewport; bring it fully on screen.
    await tester.ensureVisible(inList(find.text(s.title)));
    await tester.pumpAndSettle();
    await tester.tap(inList(find.text(s.title)));
  }

  group('master-detail (>= 744 dp)', () {
    testWidgets('12.9" portrait (1024 dp): both panes, story 1 by default, '
        'tabs not columns', (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Portrait);

      expect(listPane, findsOneWidget);
      expect(detailPane, findsOneWidget);
      expect(tester.getSize(listPane).width, MasterDetailScreen.listPaneWidth);
      expect(find.byType(DigestListScreen), findsNothing);

      // Default selection: story 1 in the pane, highlighted in the list.
      expect(inDetail(find.text(s1.title)), findsOneWidget);
      final StoryCard selected = tester
          .widgetList<StoryCard>(inList(find.byType(StoryCard)))
          .singleWhere((StoryCard c) => c.selected);
      expect(selected.story.id, s1.id);

      // 1024 < 1100: sides stay stacked inside the detail pane.
      expect(inDetail(stacked(Copy.leanGroup(Lean.left))), findsWidgets);
      expect(find.byType(PerspectiveColumns), findsNothing);
    });

    testWidgets('tapping story 3 swaps the detail in place; the URL follows',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Portrait);

      await tapStory(tester, s3);
      await tester.pump(); // one frame: no page transition to wait for
      expect(inDetail(find.text(s3.title)), findsOneWidget);
      expect(inDetail(find.text(s1.title)), findsNothing);
      expect(location(tester), '/story/${s3.id}');
      await tester.pumpAndSettle();

      // From one story to another the same page updates: no route added.
      final State<StatefulWidget> before =
          tester.state(find.byType(MasterDetailScreen));
      final int pages =
          find.byType(MasterDetailScreen, skipOffstage: false).evaluate().length;
      await tapStory(tester, s5);
      await tester.pump();
      expect(inDetail(find.text(s5.title)), findsOneWidget);
      expect(location(tester), '/story/${s5.id}');
      expect(tester.state(find.byType(MasterDetailScreen)), same(before));
      expect(
        find.byType(MasterDetailScreen, skipOffstage: false).evaluate().length,
        pages,
      );
      expect(find.byType(StoryDetailScreen), findsNothing);
    });

    testWidgets('system back returns to the default selection',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Portrait);
      await tapStory(tester, s3);
      await tester.pumpAndSettle();
      final NavigatorState nav = tester.state(find.byType(Navigator).first);
      expect(nav.canPop(), isTrue);
      nav.pop();
      await tester.pumpAndSettle();
      expect(location(tester), '/');
      expect(inDetail(find.text(s1.title)), findsOneWidget);
    });

    testWidgets('a /story/:id deep link selects that story',
        (WidgetTester tester) async {
      await pumpSidesApp(tester,
          size: ipad129Portrait, initialLocation: '/story/${s5.id}?axis=bloc');
      expect(inDetail(find.text(s5.title)), findsOneWidget);
      expect(inDetail(stacked(Copy.blocGroup(Bloc.west))), findsWidgets);
    });

    testWidgets('the selected card is announced as selected',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(tester, size: ipad129Portrait);
      bool selectedFlag(Story s) {
        SemanticsNode? n =
            tester.getSemantics(inList(find.text(s.title)));
        while (n != null) {
          if (n.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue) {
            return true;
          }
          n = n.parent;
        }
        return false;
      }

      expect(selectedFlag(s1), isTrue);
      expect(selectedFlag(s3), isFalse);
      semantics.dispose();
    });

    testWidgets('banner under the detail pane only, never beside the list',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Landscape);
      expect(inDetail(find.byKey(FakeAdsService.bannerKey)), findsOneWidget);
      expect(inList(find.byKey(FakeAdsService.bannerKey)), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StoryDetailView),
          matching: find.byKey(FakeAdsService.bannerKey),
        ),
        findsNothing,
      );
    });

    testWidgets('no banner when ad-free', (WidgetTester tester) async {
      await pumpSidesApp(tester,
          size: ipad129Landscape, harness: TestHarness(adFree: true));
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
    });

    testWidgets('no digest: list shows the offline state, detail a placeholder',
        (WidgetTester tester) async {
      await pumpSidesApp(
        tester,
        size: ipad129Landscape,
        harness: TestHarness(
          cache: InMemoryDigestCache(),
          server: (http.Request r) =>
              throw http.ClientException('Failed host lookup'),
        ),
      );
      expect(inList(find.text('You\'re offline')), findsOneWidget);
      expect(inDetail(find.text('No story selected')), findsOneWidget);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
    });

    for (final (String name, Size size) in <(String, Size)>[
      ('mini (744 dp)', ipadMiniPortrait),
      ('9.7" (768 dp)', ipad97Portrait),
      ('Air 11" (820 dp)', ipadAirPortrait),
      ('Pro 11" (834 dp)', ipad11Portrait),
    ]) {
      testWidgets('every iPad portrait is master-detail, sides stacked: '
          '$name',
          (WidgetTester tester) async {
        await pumpSidesApp(tester, size: size);
        expect(find.byType(DigestListScreen), findsNothing);
        expect(listPane, findsOneWidget);
        expect(detailPane, findsOneWidget);
        expect(tester.getSize(listPane).width,
            MasterDetailScreen.narrowListPaneWidth);
        expect(tester.getSize(detailPane).width, greaterThanOrEqualTo(380));
        expect(inDetail(find.text(s1.title)), findsOneWidget);
        expect(inDetail(stacked(Copy.leanGroup(Lean.left))), findsWidgets);
        expect(find.byType(PerspectiveColumns), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('mini portrait at 200% text reflows without overflow',
        (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSidesApp(tester, size: ipadMiniPortrait);
      expect(tester.takeException(), isNull);
      expect(detailPane, findsOneWidget);
    });

    testWidgets('10.2" landscape (1080 dp) keeps sides stacked even for two '
        'leans', (WidgetTester tester) async {
      await pumpSidesApp(tester,
          size: ipad102Landscape, initialLocation: '/story/${s8.id}');
      expect(detailPane, findsOneWidget);
      expect(inDetail(stacked(Copy.leanGroup(Lean.left))), findsWidgets);
      expect(find.byType(PerspectiveColumns), findsNothing);
    });
  });

  group('perspective columns (>= 1100 dp)', () {
    testWidgets('12.9" landscape: one column per lean present in each '
        'comparison section (headlines, emphasis)',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(tester, size: ipad129Landscape);

      // Two comparison sections, each with a column per lean.
      expect(find.byType(PerspectiveColumns), findsNWidgets(2));
      expect(column('left'), findsNWidgets(2));
      expect(column('centre'), findsNWidgets(2));
      expect(column('right'), findsNWidgets(2));
      // Equal widths.
      final double w = tester.getSize(column('left').first).width;
      expect(tester.getSize(column('centre').first).width, closeTo(w, 0.5));
      expect(tester.getSize(column('right').first).width, closeTo(w, 0.5));
      expect(w, greaterThanOrEqualTo(StoryDetailView.minColumnWidth));
      // Shared sections sit below the columns, full width.
      await tester.scrollUntilVisible(
        inDetail(find.text(Copy.agreed)),
        300,
        scrollable: detailScrollable(),
      );
      final Rect cols = tester.getRect(find.byType(PerspectiveColumns).last);
      final Rect agreed = tester.getRect(
        find.ancestor(
          of: inDetail(find.text(Copy.agreed)),
          matching: find.byType(Section),
        ),
      );
      // The Section box starts where the columns end (its 28 dp top padding
      // is inside the box), so "below" is >=, not >.
      expect(agreed.top, greaterThanOrEqualTo(cols.bottom));
      expect(agreed.left, closeTo(cols.left, 0.5));
      expect(agreed.width, closeTo(cols.width, 0.5));
      // Column headers are announced as headers.
      for (final String h in <String>[
        'Left-leaning outlets',
        'Centre outlets',
        'Right-leaning outlets',
      ]) {
        expect(tester.getSemantics(find.text(h).first),
            isSemantics(isHeader: true, label: h));
      }
      semantics.dispose();
    });

    testWidgets('only the leans present get a column (story 8)',
        (WidgetTester tester) async {
      await pumpSidesApp(tester,
          size: ipad129Landscape, initialLocation: '/story/${s8.id}');
      expect(column('left'), findsNWidgets(2));
      expect(column('centre'), findsNWidgets(2));
      expect(column('right'), findsNothing);
    });

    testWidgets('West / East as two columns; the no-contradictions line '
        'spans both', (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Landscape);
      await chooseBloc(tester);

      expect(column('west'), findsNWidgets(2));
      expect(column('east'), findsNWidgets(2));
      final Rect west = tester.getRect(column('west').first);
      final Rect east = tester.getRect(column('east').first);
      expect(west.right, lessThan(east.left));

      // Horizontal edges only: they do not change as the pane scrolls.
      await tester.scrollUntilVisible(
        find.byKey(StoryDetailView.noContradictionsKey),
        300,
        scrollable: detailScrollable(),
      );
      final Rect none =
          tester.getRect(find.byKey(StoryDetailView.noContradictionsKey));
      expect(none.left, closeTo(west.left, 0.5));
      expect(none.right, closeTo(east.right, 0.5));
    });

    testWidgets('contradictions align row by row across the bloc columns',
        (WidgetTester tester) async {
      final Map<String, Object?> json = sampleDigestJson();
      final Map<String, Object?> story =
          (json['stories']! as List<Object?>).first! as Map<String, Object?>;
      String firstOf(String bloc) {
        final Set<String> outlets = <String>{
          for (final Object? o in json['outlets']! as List<Object?>)
            if ((o! as Map<String, Object?>)['bloc'] == bloc)
              (o as Map<String, Object?>)['id']! as String,
        };
        return ((story['articles']! as List<Object?>)
                .map((Object? a) => a! as Map<String, Object?>)
                .firstWhere(
                    (Map<String, Object?> a) => outlets.contains(a['outlet_id']))
            )['id']! as String;
      }

      story['east_west_contradictions'] = <Object?>[
        <String, Object?>{
          'topic': 'Who is responsible',
          'west': <String, Object?>{
            'text': 'Western outlets attribute it to one party.',
            'sources': <String>[firstOf('west')],
          },
          'east': <String, Object?>{
            'text': 'Eastern outlets attribute it to another.',
            'sources': <String>[firstOf('east')],
          },
        },
      ];
      final TestHarness h = TestHarness(
        cache: InMemoryDigestCache(
          CachedDigest(
            body: jsonEncode(json),
            fetchedAt: sampleNow.subtract(const Duration(minutes: 15)),
            etag: '"sample"',
          ),
        ),
      );
      await pumpSidesApp(tester, size: ipad129Landscape, harness: h);
      await chooseBloc(tester);

      // Column x positions first; they do not change as the pane scrolls.
      final Rect westCol = tester.getRect(column('west').first);
      final Rect eastCol = tester.getRect(column('east').first);
      // The In brief card lists the topic too; the section's own is last.
      final Finder topic = find.text('Who is responsible').last;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('contradiction-east')),
        300,
        scrollable: detailScrollable(),
      );
      final Rect topicRect = tester.getRect(topic);
      final Rect westSide =
          tester.getRect(find.byKey(const ValueKey<String>('contradiction-west')));
      final Rect eastSide =
          tester.getRect(find.byKey(const ValueKey<String>('contradiction-east')));
      // Topic spans both columns; the sides line up under each column.
      expect(topicRect.left, closeTo(westCol.left, 0.5));
      expect(westSide.left, closeTo(westCol.left, 0.5));
      expect(westSide.right, closeTo(westCol.right, 0.5));
      expect(eastSide.left, closeTo(eastCol.left, 0.5));
      expect(eastSide.right, closeTo(eastCol.right, 0.5));
      expect(westSide.top, closeTo(eastSide.top, 0.5));
      expect(find.text('Western outlets attribute it to one party.'),
          findsOneWidget);
    });

    testWidgets('11" landscape (1194 dp): three leans stay stacked, '
        'two leans and the blocs fit as columns', (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad11Landscape);
      expect(inDetail(stacked(Copy.leanGroup(Lean.left))), findsWidgets);
      expect(find.byType(PerspectiveColumns), findsNothing);
      await chooseBloc(tester);
      expect(column('west'), findsWidgets);

      await tapStory(tester, s8);
      await tester.pumpAndSettle();
      // The axis carries over to the next story: still West / East.
      expect(location(tester), '/story/${s8.id}?axis=bloc');
      expect(column('west'), findsWidgets);
      await tester.ensureVisible(axisSwitch(Copy.axisLean));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisLean));
      await tester.pumpAndSettle();
      expect(column('left'), findsWidgets);
      expect(column('centre'), findsWidgets);
    });

    testWidgets('text scale 2.0 collapses columns back to stacked sides',
        (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSidesApp(tester, size: ipad129Landscape);
      expect(tester.takeException(), isNull);
      expect(find.byType(PerspectiveColumns), findsNothing);
      expect(inDetail(stacked(Copy.leanGroup(Lean.left))), findsWidgets);
      await chooseBloc(tester);
      expect(find.byType(PerspectiveColumns), findsNothing);
      expect(inDetail(stacked(Copy.blocGroup(Bloc.west))), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark mode renders the columns without errors',
        (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpSidesApp(tester, size: ipad129Landscape);
      expect(
        Theme.of(tester.element(detailPane)).brightness,
        Brightness.dark,
      );
      expect(column('left'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('rotation and resizing', () {
    testWidgets('phone -> tablet -> phone keeps the story and axis',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, initialLocation: '/story/${s3.id}');
      expect(find.byType(StoryDetailScreen), findsOneWidget);
      // Story 3's In brief card pushes the axis switch below the fold.
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(find.text('Eastern outlets'), findsWidgets);

      await resize(tester, ipad129Landscape);
      expect(find.byType(StoryDetailScreen), findsNothing);
      expect(inDetail(find.text(s3.title)), findsOneWidget);
      expect(column('west'), findsWidgets, reason: 'axis kept: West / East');

      await resize(tester, ipad129Portrait);
      expect(find.byType(PerspectiveColumns), findsNothing);
      expect(inDetail(find.text('Eastern outlets')), findsWidgets,
          reason: 'axis kept: East still on the page');

      await resize(tester, phoneSize);
      expect(find.byType(MasterDetailScreen), findsNothing);
      expect(find.byType(StoryDetailScreen), findsOneWidget);
      expect(find.text('3 of 10'), findsOneWidget);
      expect(find.text('Eastern outlets'), findsWidgets);

      // Back still leads to the phone list.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DigestListScreen), findsOneWidget);
    });

    testWidgets('the list keeps its scroll position on the first selection',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, size: ipad129Landscape);
      final Story s10 = digest.stories[9];
      await tester.scrollUntilVisible(
        inList(find.text(s10.title)),
        300,
        scrollable: listScrollable(),
      );
      final double offset = tester
          .state<ScrollableState>(listScrollable())
          .position
          .pixels;
      expect(offset, greaterThan(0));
      await tester.tap(inList(find.text(s10.title)));
      await tester.pumpAndSettle();
      expect(inDetail(find.text(s10.title)), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(listScrollable())
            .position
            .pixels,
        closeTo(offset, 0.5),
      );
    });
  });

  group('phone layout unchanged (< 744 dp)', () {
    testWidgets('390x844: list, then a pushed story page',
        (WidgetTester tester) async {
      await pumpSidesApp(tester);
      expect(find.byType(DigestListScreen), findsOneWidget);
      expect(find.byType(MasterDetailScreen), findsNothing);
      await tester.tap(find.text(s1.title));
      await tester.pumpAndSettle();
      expect(find.byType(StoryDetailScreen), findsOneWidget);
      expect(find.text('1 of 10'), findsOneWidget);
      expect(stacked(Copy.leanGroup(Lean.left)), findsWidgets);
      expect(find.byType(PerspectiveColumns), findsNothing);
    });

    testWidgets('743 dp is still the phone layout',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, size: justBelowTablet);
      expect(find.byType(DigestListScreen), findsOneWidget);
      expect(find.byType(MasterDetailScreen), findsNothing);
    });
  });
}
