import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/search/data/topic_repository.dart';
import 'package:sides/features/search/presentation/search_view.dart';
import 'package:sides/features/story/presentation/widgets/in_brief_card.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

import '../fixtures/fixtures.dart';
import '../helpers/pump_app.dart';

/// The Search tab: archive search on the device, then the on-demand topic
/// comparison from the fake service.
void main() {
  final Digest digest = sampleDigest();

  /// The sample digest re-dated as an archive day.
  Digest archived(String date) {
    final Map<String, Object?> j = sampleDigestJson()..['date'] = date;
    return Digest.fromJson(j);
  }

  Future<TestHarness> openSearch(WidgetTester tester, {TestHarness? h}) async {
    final TestHarness harness = await pumpSidesApp(tester, harness: h);
    await tester.tap(find.text(Copy.tabSearch));
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(SearchView.fieldKey), q);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  /// The topic panel sits under the results: bring its button on screen.
  Future<void> tapAnalyse(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(SearchView.analyseKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SearchView.analyseKey));
  }

  testWidgets('a search finds stories in today\'s digest and the archive, '
      'newest first within equal scores', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.archive.days['2026-10-13'] = archived('2026-10-13');
    await openSearch(tester, h: h);
    expect(find.text(Copy.searchTitle), findsOneWidget);

    await search(tester, 'Pope cancer');
    expect(h.archive.indexCalls, 1);
    expect(find.text(Copy.searchResults(2, 2)), findsOneWidget);
    expect(find.text(Copy.today), findsOneWidget);
    expect(find.text('Tue 13 Oct'), findsOneWidget);
    expect(find.text(digest.stories.first.title), findsNWidgets(2));
  });

  testWidgets('a hit from today opens the normal story page; an archive hit '
      'opens the archived story with its own previous / next',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.archive.days['2026-10-13'] = archived('2026-10-13');
    await openSearch(tester, h: h);
    await search(tester, 'Pope cancer');

    await tester.tap(find.text(digest.stories.first.title).last);
    await tester.pumpAndSettle();
    expect(find.text('1 of 10'), findsOneWidget);
    expect(find.byType(StoryDetailView), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(SearchView.fieldKey), findsOneWidget,
        reason: 'back returns to the search tab with its results');
    expect(find.text(Copy.searchResults(2, 2)), findsOneWidget);
  });

  testWidgets('no archive match: the topic panel offers a comparison; '
      'no_match, capped and rate limits are explained',
      (WidgetTester tester) async {
    final TestHarness h = await openSearch(tester);
    await search(tester, 'zebra migration');
    expect(find.text(Copy.searchResults(0, 1)), findsOneWidget);
    expect(find.text(Copy.topicPitchNoHits), findsOneWidget);

    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(h.topic.queries, <String>['zebra migration']);
    expect(find.text(Copy.topicNoMatch), findsOneWidget);

    h.topic.outcome = const TopicCapped();
    await search(tester, 'zebra stripes');
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(find.text(Copy.topicCapped), findsOneWidget);

    h.topic.outcome = const TopicRateLimited();
    await search(tester, 'zebra crossing');
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(find.text(Copy.topicRateLimited), findsOneWidget);
  });

  testWidgets('a ready topic opens as a story page with the In brief card',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    final Map<String, Object?> j = sampleDigestJson();
    final List<Object?> stories = j['stories']! as List<Object?>;
    j['stories'] = <Object?>[stories[1]];
    final Map<String, Object?> s = stories[1]! as Map<String, Object?>;
    s['title'] = 'Starlink ukraine';
    s['rank'] = 1;
    s['summary'] = <String, Object?>{
      'text': 'Ukraine says its Starlink access was restricted.',
      'sources': <String>[
        ((s['articles']! as List<Object?>).first! as Map<String, Object?>)['id']!
            as String,
      ],
    };
    final Digest topicDigest = Digest.fromJson(jsonDecode(jsonEncode(j)) as Map<String, Object?>);
    h.topic.outcome = TopicReady(topicDigest, cached: false);
    await openSearch(tester, h: h);
    await search(tester, 'zebra starlink');
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(find.text(Copy.topicReady), findsOneWidget);
    expect(find.text('Starlink ukraine'), findsOneWidget);

    await tester.ensureVisible(find.text(Copy.compare));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Copy.compare));
    await tester.pumpAndSettle();
    expect(find.byType(StoryDetailView), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.byKey(InBriefCard.cardKey), findsOneWidget);
    expect(
      find.text('Ukraine says its Starlink access was restricted.'),
      findsOneWidget,
    );
  });

  testWidgets('a working comparison shows progress and the failure message '
      'when the service fails', (WidgetTester tester) async {
    final TestHarness h = TestHarness();
    h.topic.outcome = const TopicFailed('The topic service is down.');
    h.topic.gate = Completer<void>();
    await openSearch(tester, h: h);
    await search(tester, 'zebra');
    await tapAnalyse(tester);
    await tester.pump();
    expect(find.text(Copy.topicWorking), findsOneWidget);
    h.topic.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('The topic service is down.'), findsOneWidget);
    expect(find.text(Copy.topicRetry), findsOneWidget);
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
