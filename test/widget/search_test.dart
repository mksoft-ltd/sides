import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show Offset, Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/search/data/topic_repository.dart';
import 'package:sides/features/search/presentation/search_controller.dart';
import 'package:sides/features/search/presentation/search_progress.dart';
import 'package:sides/features/search/presentation/search_view.dart';
import 'package:sides/features/story/presentation/widgets/in_brief_card.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// The Search tab: cheapest source first (this phone, the archive online,
/// the shared cache, then a new comparison only when today has nothing),
/// results streaming into one list, and a progress panel that explains the
/// steps but only appears when a search is slow.
void main() {
  final Digest digest = sampleDigest();

  Digest archived(String date) {
    final Map<String, Object?> j = sampleDigestJson()..['date'] = date;
    return Digest.fromJson(j);
  }

  /// A one-story topic digest, as the service returns it.
  Digest topicDigest() {
    final Map<String, Object?> j = sampleDigestJson();
    final List<Object?> stories = j['stories']! as List<Object?>;
    final Map<String, Object?> s = stories[1]! as Map<String, Object?>;
    j['stories'] = <Object?>[s];
    s['title'] = 'Starlink ukraine';
    s['rank'] = 1;
    s['summary'] = <String, Object?>{
      'text': 'Ukraine says its Starlink access was restricted.',
      'sources': <String>[
        ((s['articles']! as List<Object?>).first! as Map<String, Object?>)['id']!
            as String,
      ],
    };
    return Digest.fromJson(jsonDecode(jsonEncode(j)) as Map<String, Object?>);
  }

  Future<TestHarness> openSearch(WidgetTester tester, {TestHarness? h}) async {
    final TestHarness harness = await pumpSidesApp(tester, harness: h);
    await tester.tap(find.text(Copy.tabSearch));
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(SearchView.fieldKey), q);
    await tester.testTextInput.receiveAction(TextInputAction.search);
  }

  Future<void> search(WidgetTester tester, String q) async {
    await type(tester, q);
    await tester.pumpAndSettle();
  }

  testWidgets('phone first: saved days are searched without downloading; '
      'missing days are fetched and merged', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.archive.days['2026-10-13'] = archived('2026-10-13');
    h.archive.days['2026-10-12'] = archived('2026-10-12');
    h.archive.onPhone.add('2026-10-13');
    await openSearch(tester, h: h);

    await search(tester, 'Pope cancer');
    expect(h.archive.downloaded, <String>['2026-10-12'],
        reason: 'the day saved on the phone is never downloaded again');
    expect(find.text(Copy.searchResults(3, 3)), findsOneWidget);
    expect(find.text('Tue 13 Oct'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mon 12 Oct'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mon 12 Oct'), findsOneWidget);
  });

  testWidgets('today already covers the words: no comparison is started',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    await openSearch(tester, h: h);
    await search(tester, 'Pope cancer');
    expect(h.topic.queries, isEmpty);
    expect(find.byKey(SearchView.topicCardKey), findsNothing);
    expect(find.text(Copy.today), findsOneWidget);
  });

  testWidgets('nothing today: the comparison starts by itself and opens as a '
      'story page with In brief', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.outcome = TopicReady(topicDigest(), cached: false);
    await openSearch(tester, h: h);
    await search(tester, 'zebra starlink');
    expect(h.topic.peeks, <String>['zebra starlink'], reason: 'free cache first');
    expect(h.topic.queries, <String>['zebra starlink'], reason: 'then compared');
    expect(find.byKey(SearchView.topicCardKey), findsOneWidget);
    expect(find.text(Copy.topicCardLabel), findsOneWidget);

    await tester.tap(find.byKey(SearchView.topicCardKey));
    await tester.pumpAndSettle();
    expect(find.byType(StoryDetailView), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.byKey(InBriefCard.cardKey), findsOneWidget);
  });

  testWidgets('another reader already asked: the shared cache answers and '
      'nothing new is paid for', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.peekOutcome = TopicReady(topicDigest(), cached: true);
    await openSearch(tester, h: h);
    await search(tester, 'zebra starlink');
    expect(h.topic.queries, isEmpty);
    expect(find.text(Copy.topicCardCached), findsOneWidget);
  });

  testWidgets('a comparison already on this phone: no network for it at all',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.phone = TopicReady(topicDigest(), cached: false);
    await openSearch(tester, h: h);
    await search(tester, 'zebra starlink');
    expect(h.topic.peeks, isEmpty);
    expect(h.topic.queries, isEmpty);
    expect(find.byKey(SearchView.topicCardKey), findsOneWidget);
  });

  testWidgets('a fast search never shows the progress panel',
      (WidgetTester tester) async {
    await openSearch(tester);
    await type(tester, 'Pope cancer');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(SearchProgress.panelKey), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(SearchProgress.panelKey), findsNothing);
  });

  testWidgets('a slow comparison shows the steps, what each one is doing, '
      'placeholders and a rotating line', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.outcome = TopicReady(topicDigest(), cached: false);
    h.topic.gate = Completer<void>();
    await openSearch(tester, h: h);
    await type(tester, 'zebra starlink');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(SearchProgress.panelKey), findsOneWidget);
    expect(find.text(Copy.stepTitle(SearchStep.phone, StepStatus.done)),
        findsOneWidget);
    expect(find.text(Copy.stepTitle(SearchStep.archive, StepStatus.done)),
        findsOneWidget);
    expect(find.text(Copy.stepTitle(SearchStep.compare, StepStatus.running)),
        findsOneWidget);
    expect(find.textContaining('30 to 60 seconds'), findsOneWidget);
    expect(find.text(Copy.compareStage(Duration.zero)), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pump();
    expect(find.byType(ResultSkeleton), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pump();

    await tester.pump(const Duration(seconds: 20));
    expect(find.text(Copy.compareStage(const Duration(seconds: 20))),
        findsOneWidget);

    h.topic.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(SearchProgress.panelKey), findsNothing);
    expect(find.byType(ResultSkeleton), findsNothing);
    expect(find.byKey(SearchView.topicCardKey), findsOneWidget);
  });

  testWidgets('no outlet covered the words: one plain line, no card',
      (WidgetTester tester) async {
    await openSearch(tester);
    await search(tester, 'zebra migration');
    expect(find.text(Copy.searchNothing), findsOneWidget);
    expect(find.byKey(SearchView.topicCardKey), findsNothing);
  });

  testWidgets('daily limit and hourly limit are explained',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.outcome = const TopicCapped();
    await openSearch(tester, h: h);
    await search(tester, 'zebra stripes');
    expect(find.text(Copy.topicCapped), findsOneWidget);

    h.topic.outcome = const TopicRateLimited();
    await search(tester, 'zebra crossing');
    expect(find.text(Copy.topicRateLimited), findsOneWidget);
  });

  testWidgets('a failed comparison says why and offers to try again',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.outcome = const TopicFailed('The topic service is down.');
    await openSearch(tester, h: h);
    await search(tester, 'zebra');
    expect(find.text('The topic service is down.'), findsOneWidget);
    h.topic.outcome = TopicReady(topicDigest(), cached: false);
    await tester.ensureVisible(find.byKey(SearchView.retryKey));
    await tester.tap(find.byKey(SearchView.retryKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SearchView.topicCardKey), findsOneWidget);
    expect(h.topic.queries, hasLength(2));
  });

  testWidgets('the archive being unreachable is said, and today is still '
      'searched', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.archive.offline = true;
    await openSearch(tester, h: h);
    await search(tester, 'Pope');
    expect(find.text(Copy.archiveUnavailable), findsOneWidget);
    expect(find.text(digest.stories.first.title), findsOneWidget);
  });
}
