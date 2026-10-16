import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/digest/presentation/screens/master_detail_screen.dart';
import 'package:sides/features/story/presentation/providers/story_view_controller.dart';
import 'package:sides/features/story/presentation/widgets/source_pills.dart';
import 'package:sides/features/story/presentation/widgets/sources_list.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';
import 'package:sides/shared/widgets/coverage_indicator.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// Screen-reader labels pinned to hand-written literals (the existing tests
/// build the expected label from the same function the widget uses, which
/// proves agreement, not wording), plus a 200 % text sweep of every story,
/// both axes, scrolled top to bottom, on the smallest phone
/// iOS 15 still supports and on two iPad sizes.
void main() {
  final Digest digest = sampleDigest();

  group('semantics labels (literal)', () {
    test('coverage label wording, both axes, including the zero-lean case', () {
      expect(
        CoverageIndicator.semanticsLabel(
          const Coverage(left: 6, centre: 3, right: 2, west: 11, east: 1),
        ),
        'Coverage by political lean: 6 left, 3 centre, 2 right. '
        'Coverage by West and East: 11 Western, 1 Eastern.',
      );
      expect(
        CoverageIndicator.semanticsLabel(
          const Coverage(left: 0, centre: 0, right: 0, west: 0, east: 4),
        ),
        'Coverage by political lean: no lean-rated outlets. '
        'Coverage by West and East: 0 Western, 4 Eastern.',
      );
    });

    testWidgets('story 1 card announces its real counts', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(tester);
      // Story 1 (c8bbc1a001c2) in the sample: 6/3/2 by lean, 11/1 by bloc.
      expect(
        find.bySemanticsLabel(
          'Coverage by political lean: 6 left, 3 centre, 2 right. '
          'Coverage by West and East: 11 Western, 1 Eastern.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('story 7 card announces the zero centre and right counts', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(tester);
      final Finder label = find.bySemanticsLabel(
        'Coverage by political lean: 2 left, 0 centre, 0 right. '
        'Coverage by West and East: 2 Western, 4 Eastern.',
      );
      // The front page has a lens row and a carousel: scroll the main list.
      await tester.scrollUntilVisible(
        label,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(label, findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      'the expanded coverage on the story page is one labelled node',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await pumpSidesApp(
          tester,
          initialLocation: '/story/${digest.stories.first.id}',
        );
        final Finder node = find.bySemanticsLabel(
          'Coverage by political lean: 6 left, 3 centre, 2 right. '
          'Coverage by West and East: 11 Western, 1 Eastern.',
        );
        expect(node, findsOneWidget);
        // The legend text under the bars is excluded, so it is not read twice.
        expect(find.bySemanticsLabel('Left 6'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('a sources link reads its count; the sheet row it opens '
        'reads outlet, headline and that it opens a browser', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      // Article 7809db6abcec (Fox News) is the first source of story 1's
      // first agreed fact.
      const String rowLabel =
          'Source: Fox News — Pope Leo diagnosed with lung '
          'cancer after surgeons remove part of right lung, Vatican says. '
          'Opens in your browser.';
      final Finder scrollable = find
          .descendant(
            of: find.byType(StoryDetailView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(Copy.agreed),
        300,
        scrollable: scrollable,
      );
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      final Finder link = find.bySemanticsLabel(
        RegExp(r'^\d+ sources?\. Shows the articles behind this point\.$'),
      );
      expect(link, findsWidgets);
      expect(
        tester.getSemantics(link.first).getSemanticsData().flagsCollection
            .isButton,
        isTrue,
      );

      await tester.tap(link.first);
      await tester.pumpAndSettle();
      final Finder row = find.bySemanticsLabel(rowLabel);
      expect(row, findsOneWidget);
      final SemanticsData data = tester.getSemantics(row).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isLink, isTrue);
      semantics.dispose();
    });

    // Regression for F2 (docs/TEST_PLAN.md): Semantics(excludeSemantics:
    // true) without onTap stripped the InkWell's tap action, so TalkBack and
    // Switch Access could not open a source.
    testWidgets('a sources link, a sheet row and a Sources row expose a tap '
        'action to assistive tech', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestHarness h = await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      final Finder scrollable = find
          .descendant(
            of: find.byType(StoryDetailView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(SourcesLink).first,
        200,
        scrollable: scrollable,
      );
      final SemanticsNode link = tester.getSemantics(
        find.byType(SourcesLink).first,
      );
      expect(
        link.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'TalkBack / Switch Access activate via the tap action',
      );

      // The link's action opens the sheet; the sheet row's action opens
      // the article.
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(r'^\d+ sources?\. Shows the articles')).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SourcesSheet), findsOneWidget);
      final FinderBase<SemanticsNode> sheetRow =
          find.semantics.byLabel(RegExp(r'^Source: .*Opens in ')).first;
      expect(
        tester.getSemantics(find.byType(SourceTile).first)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      tester.semantics.tap(sheetRow);
      await tester.pumpAndSettle();
      expect(h.launcher.opened, hasLength(1));
      // Close the sheet.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(SourcesSheet), findsNothing);

      final Finder sourcesHeader = find.text(
        '${Copy.sources} (${digest.stories.first.articles.length})',
      );
      await tester.scrollUntilVisible(
        sourcesHeader,
        400,
        scrollable: scrollable,
      );
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      final Finder row = find.bySemanticsLabel(RegExp(r'^Source: .*Opens in '));
      expect(
        tester
            .getSemantics(row.last)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    });

    testWidgets('every tappable on the story page meets the 48 dp minimum', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${digest.stories.first.id}',
      );
      final Finder chips = find.byType(InkWell).hitTestable();
      expect(chips, findsWidgets);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  group('text scale 2.0: every story, both axes, top to bottom', () {
    Future<void> withTextScale(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    /// Scrolls [scrollable] from top to bottom in viewport-sized steps,
    /// failing on the first layout error (overflow) with where it happened.
    Future<void> sweep(
      WidgetTester tester,
      Finder scrollable,
      String what,
    ) async {
      final ScrollableState st = tester.state<ScrollableState>(scrollable);
      st.position.jumpTo(0);
      await tester.pump();
      int steps = 0;
      while (true) {
        final Object? err = tester.takeException();
        expect(
          err,
          isNull,
          reason: '$what at offset ${st.position.pixels.round()}',
        );
        if (st.position.pixels >= st.position.maxScrollExtent) break;
        st.position.jumpTo(
          math.min(
            st.position.pixels + st.position.viewportDimension * 0.8,
            st.position.maxScrollExtent,
          ),
        );
        await tester.pump();
        expect(++steps, lessThan(400), reason: '$what never reached the end');
      }
    }

    /// pumpSidesApp over an existing app reuses its router (and harness), so
    /// unmount first to start each page from a fresh launch.
    Future<void> relaunch(
      WidgetTester tester,
      Size size,
      String location, {
      TestHarness? harness,
    }) async {
      await tester.pumpWidget(const SizedBox());
      await pumpSidesApp(
        tester,
        size: size,
        initialLocation: location,
        harness: harness,
      );
    }

    Finder detailScrollable() => find
        .descendant(
          of: find.byType(StoryDetailView),
          matching: find.byType(Scrollable),
        )
        .first;

    /// Every axis and tab of [s], via the same provider the tabs drive.
    Future<void> sweepStory(WidgetTester tester, Story s, String where) async {
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(StoryDetailView)),
      );
      expect(
        find.descendant(
          of: find.byType(StoryDetailView),
          matching: find.text(s.title),
        ),
        findsOneWidget,
        reason: '$where: story ${s.rank} is on screen',
      );
      StoryViewController ctl() => c.read(storyViewProvider(s.id).notifier);
      for (final PerspectiveAxis axis in PerspectiveAxis.values) {
        ctl().setAxis(axis);
        await tester.pump();
        await sweep(
          tester,
          detailScrollable(),
          '$where story ${s.rank} ${axis.name}',
        );
      }
    }

    const Map<String, Size> phones = <String, Size>{
      'iPhone SE 1st gen (320x568, smallest on iOS 15)': Size(320, 568),
      'small Android (360x640)': Size(360, 640),
      'brief phone (390x844)': phoneSize,
    };

    for (final MapEntry<String, Size> phone in phones.entries) {
      testWidgets('phone ${phone.key}: list and every story page', (
        WidgetTester tester,
      ) async {
        await withTextScale(tester);
        await pumpSidesApp(tester, size: phone.value);
        await sweep(tester, find.byType(Scrollable).first, 'list');
        for (final Story s in digest.stories) {
          await relaunch(tester, phone.value, '/story/${s.id}');
          await sweepStory(tester, s, phone.key);
        }
      });
    }

    testWidgets('phone 320 dp: settings and outlets screens', (
      WidgetTester tester,
    ) async {
      await withTextScale(tester);
      await pumpSidesApp(
        tester,
        size: const Size(320, 568),
        initialLocation: '/settings',
      );
      await sweep(tester, find.byType(Scrollable).first, 'settings');
      await relaunch(tester, const Size(320, 568), '/settings/outlets');
      await sweep(tester, find.byType(Scrollable).first, 'outlets');
    });

    testWidgets('phone 320 dp: offline empty state and offline note', (
      WidgetTester tester,
    ) async {
      await withTextScale(tester);
      await pumpSidesApp(
        tester,
        size: const Size(320, 568),
        harness: TestHarness(
          cache: InMemoryDigestCache(),
          server: (http.Request _) => throw http.ClientException('offline'),
        ),
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await relaunch(
        tester,
        const Size(320, 568),
        '/',
        harness: TestHarness(
          cache: InMemoryDigestCache(
            CachedDigest(
              body: sampleDigestBody(),
              fetchedAt: sampleNow.subtract(const Duration(days: 2)),
            ),
          ),
          server: (http.Request _) => throw http.ClientException('offline'),
        ),
      );
      expect(
        find.textContaining('Couldn\'t check for a newer digest'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    const Map<String, Size> tablets = <String, Size>{
      'iPad mini portrait (744 dp)': Size(744, 1133),
      '12.9" landscape (1366 dp)': Size(1366, 1024),
    };

    for (final MapEntry<String, Size> t in tablets.entries) {
      testWidgets('tablet ${t.key}: list pane and every story in the detail '
          'pane', (WidgetTester tester) async {
        await withTextScale(tester);
        await pumpSidesApp(tester, size: t.value);
        await sweep(
          tester,
          find
              .descendant(
                of: find.byKey(MasterDetailScreen.listPaneKey),
                matching: find.byType(Scrollable),
              )
              .first,
          'list pane',
        );
        for (final Story s in digest.stories) {
          await relaunch(tester, t.value, '/story/${s.id}');
          await sweepStory(tester, s, t.key);
        }
      });
    }

    testWidgets(
      'a 9-word blindspot chip and an outlet count reflow on 320 dp',
      (WidgetTester tester) async {
        await withTextScale(tester);
        final Story s7 = digest.stories[6];
        await pumpSidesApp(
          tester,
          size: const Size(320, 568),
          initialLocation: '/story/${s7.id}',
        );
        final Finder chip = find.text(Copy.blindspotLean(Lean.left));
        await tester.scrollUntilVisible(
          chip,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(chip, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
