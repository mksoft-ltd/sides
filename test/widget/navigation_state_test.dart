import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/digest/presentation/screens/digest_list_screen.dart';
import 'package:sides/features/digest/presentation/screens/master_detail_screen.dart';
import 'package:sides/features/story/presentation/screens/story_detail_screen.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Deep links (`/story/:id?axis=bloc`), stale links, cold-start links, and
/// the per-story axis state across navigation and layout swaps.
void main() {
  final Digest digest = sampleDigest();
  final Story s1 = digest.stories[0];
  final Story s3 = digest.stories[2];
  const Size tabletPortrait = Size(1024, 1366);
  const Size tabletLandscape = Size(1366, 1024);

  /// A side's heading, present only while that axis is shown.
  Finder side(String label) => find.text(label);
  Finder detailPane() => find.byKey(MasterDetailScreen.detailPaneKey);
  Finder inDetail(Finder f) => find.descendant(of: detailPane(), matching: f);
  Finder axisSwitch(String label) => find.descendant(
    of: find.byType(SegmentedButton<PerspectiveAxis>),
    matching: find.text(label),
  );
  Finder column(String wire) => find.byKey(PerspectiveColumns.keyFor(wire));

  String location(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(Scaffold).last),
  ).routerDelegate.currentConfiguration.uri.toString();

  group('deep links', () {
    testWidgets('a stale story id on phone: friendly message, no banner, '
        'and back leads to today\'s list (no dead end)', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(tester, initialLocation: '/story/000000000000');
      expect(find.text('Story not available'), findsOneWidget);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DigestListScreen), findsOneWidget);
      expect(find.text(s1.title), findsOneWidget);
    });

    testWidgets('a stale story id on tablet: list stays usable and a tap '
        'recovers', (WidgetTester tester) async {
      await pumpSidesApp(
        tester,
        size: tabletPortrait,
        initialLocation: '/story/000000000000',
      );
      expect(inDetail(find.text('Story not available')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(MasterDetailScreen.listPaneKey),
          matching: find.text(s3.title),
        ),
      );
      await tester.pumpAndSettle();
      expect(inDetail(find.text(s3.title)), findsOneWidget);
      expect(location(tester), '/story/${s3.id}');
    });

    testWidgets('an unknown ?axis= value falls back to Political lean', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(
        tester,
        initialLocation: '/story/${s1.id}?axis=everything',
      );
      expect(side(Copy.leanGroup(Lean.left)), findsWidgets);
      expect(side(Copy.blocGroup(Bloc.west)), findsNothing);
    });

    testWidgets('?axis=bloc at 1366 dp opens the West / East columns', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(
        tester,
        size: tabletLandscape,
        initialLocation: '/story/${s1.id}?axis=bloc',
      );
      expect(column('west'), findsWidgets);
      expect(column('east'), findsWidgets);
      expect(column('left'), findsNothing);
    });

    testWidgets('cold start from a deep link with no cache: loading, then '
        'the story once the digest arrives', (WidgetTester tester) async {
      final TestHarness h = TestHarness(
        cache: InMemoryDigestCache(),
        server: (http.Request _) => http.Response.bytes(
          utf8.encode(sampleDigestBody()),
          200,
          headers: <String, String>{'etag': '"v1"'},
        ),
      );
      await pumpSidesApp(
        tester,
        harness: h,
        initialLocation: '/story/${s1.id}?axis=bloc',
      );
      expect(h.requests, hasLength(1));
      expect(find.text('1 of 10'), findsOneWidget);
      expect(side(Copy.blocGroup(Bloc.west)), findsWidgets);
      expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
    });
  });

  group('axis state', () {
    testWidgets('tablet: the reader\'s axis carries over to the next story', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(tester, size: tabletPortrait);
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(inDetail(side(Copy.blocGroup(Bloc.west))), findsWidgets);

      await tester.tap(
        find.descendant(
          of: find.byKey(MasterDetailScreen.listPaneKey),
          matching: find.text(s3.title),
        ),
      );
      await tester.pumpAndSettle();
      expect(location(tester), '/story/${s3.id}?axis=bloc');
      expect(inDetail(find.text(s3.title)), findsOneWidget);
      expect(inDetail(side(Copy.blocGroup(Bloc.west))), findsWidgets);
      expect(inDetail(side(Copy.leanGroup(Lean.left))), findsNothing);
    });

    testWidgets('phone: reopening a story afresh starts from its route axis', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(tester);
      await tester.tap(find.text(s1.title));
      await tester.pumpAndSettle();
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(side(Copy.blocGroup(Bloc.west)), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(s1.title));
      await tester.pumpAndSettle();
      expect(
        side(Copy.leanGroup(Lean.left)),
        findsWidgets,
        reason: 'state is per visit (autoDispose), not sticky forever',
      );
    });

    testWidgets('phone: a story\'s state is its own; another story starts '
        'at Political lean', (WidgetTester tester) async {
      await pumpSidesApp(tester, initialLocation: '/story/${s1.id}');
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(side(Copy.blocGroup(Bloc.west)), findsWidgets);

      unawaited(
        GoRouter.of(
          tester.element(find.byType(StoryDetailScreen)),
        ).push<void>('/story/${s3.id}'),
      );
      await tester.pumpAndSettle();
      expect(side(Copy.leanGroup(Lean.left)), findsWidgets);
      expect(side(Copy.blocGroup(Bloc.west)), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        side(Copy.blocGroup(Bloc.west)),
        findsWidgets,
        reason: 'story 1 is still on screen underneath, so its axis stays',
      );
    });

    testWidgets('the axis survives phone -> columns -> phone', (
      WidgetTester tester,
    ) async {
      await pumpSidesApp(tester, initialLocation: '/story/${s1.id}');
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(side(Copy.blocGroup(Bloc.east)), findsWidgets);

      tester.view.physicalSize = tabletLandscape * 3;
      await tester.pumpAndSettle();
      expect(column('east'), findsWidgets);

      tester.view.physicalSize = phoneSize * 3;
      await tester.pumpAndSettle();
      expect(find.byType(StoryDetailScreen), findsOneWidget);
      expect(side(Copy.blocGroup(Bloc.east)), findsWidgets);
      expect(side(Copy.leanGroup(Lean.left)), findsNothing);
    });
  });

  group('degenerate digests', () {
    InMemoryDigestCache cacheWith(Map<String, Object?> json) =>
        InMemoryDigestCache(
          CachedDigest(
            body: jsonEncode(json),
            fetchedAt: sampleNow.subtract(const Duration(minutes: 5)),
          ),
        );

    testWidgets(
      'a digest with zero stories renders on phone without crashing',
      (WidgetTester tester) async {
        final Map<String, Object?> j = sampleDigestJson()
          ..['stories'] = <Object?>[];
        await pumpSidesApp(tester, harness: TestHarness(cache: cacheWith(j)));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('0 top stories'), findsOneWidget);
      },
    );

    testWidgets(
      'a digest with zero stories renders on tablet without crashing',
      (WidgetTester tester) async {
        final Map<String, Object?> j = sampleDigestJson()
          ..['stories'] = <Object?>[];
        await pumpSidesApp(
          tester,
          harness: TestHarness(cache: cacheWith(j)),
          size: tabletLandscape,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(StoryDetailView), findsNothing);
        expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      },
    );

    testWidgets('a story whose every analysis array is empty (failed '
        'analysis) still renders its sources', (WidgetTester tester) async {
      final Map<String, Object?> j = sampleDigestJson();
      final Map<String, Object?> st =
          (j['stories']! as List<Object?>).first! as Map<String, Object?>;
      for (final String k in <String>[
        'agreed_facts',
        'framing',
        'omissions',
        'contested_claims',
        'opinion',
        'framing_by_bloc',
        'east_west_contradictions',
      ]) {
        st[k] = <Object?>[];
      }
      await pumpSidesApp(
        tester,
        harness: TestHarness(cache: cacheWith(j)),
        initialLocation: '/story/${s1.id}',
      );
      expect(tester.takeException(), isNull);
      final Finder sources = find.text(
        '${Copy.sources} (${s1.articles.length})',
      );
      final Finder scrollable = find
          .descendant(
            of: find.byType(StoryDetailView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(sources, 300, scrollable: scrollable);
      expect(sources, findsOneWidget);
      await tester.scrollUntilVisible(
        axisSwitch(Copy.axisBloc),
        -300,
        scrollable: scrollable,
      );
      await tester.ensureVisible(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      await tester.tap(axisSwitch(Copy.axisBloc));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
