import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/digest/presentation/widgets/story_card.dart';
import 'package:sides/shared/widgets/coverage_indicator.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  final Digest digest = sampleDigest();

  testWidgets('renders all 10 stories with coverage bars, in rank order',
      (WidgetTester tester) async {
    final TestHarness h = await pumpSidesApp(tester);
    expect(h.requests, isEmpty, reason: 'fresh cache: no refetch at launch');

    final Finder list = find.byType(Scrollable).first;
    final Set<String> seen = <String>{};
    for (final Story s in digest.stories) {
      await tester.scrollUntilVisible(find.text(s.title), 200,
          scrollable: list);
      seen.add(s.title);
      final Finder card = find.ancestor(
        of: find.text(s.title),
        matching: find.byType(StoryCard),
      );
      expect(
        find.descendant(of: card, matching: find.byType(CoverageIndicator)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.bySemanticsLabel(
            CoverageIndicator.semanticsLabel(s.coverage),
          ),
        ),
        findsOneWidget,
      );
    }
    expect(seen, hasLength(10));
  });

  testWidgets('story 7 shows the left-only blindspot chip; story 1 none',
      (WidgetTester tester) async {
    await pumpSidesApp(tester);
    expect(find.text('Only left-leaning outlets covered this'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Only left-leaning outlets covered this'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final Finder chip = find.text('Only left-leaning outlets covered this');
    expect(chip, findsOneWidget);
    final Finder card =
        find.ancestor(of: chip, matching: find.byType(StoryCard));
    expect(
      find.descendant(of: card, matching: find.text(digest.stories[6].title)),
      findsOneWidget,
    );
  });

  testWidgets('shows the generated date and a Last updated line',
      (WidgetTester tester) async {
    await pumpSidesApp(tester);
    expect(find.text('Wednesday 14 October 2026'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);
  });

  testWidgets('banner slot sits under the list', (WidgetTester tester) async {
    final TestHarness h = await pumpSidesApp(tester);
    expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
    expect(h.ads.bannersBuilt, greaterThan(0));
  });

  testWidgets('no banner at all when the ad-free unlock is owned',
      (WidgetTester tester) async {
    final TestHarness h =
        await pumpSidesApp(tester, harness: TestHarness(adFree: true));
    expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
    expect(h.ads.bannersBuilt, 0);
  });

  testWidgets('offline with no cache: friendly empty state, Retry refetches',
      (WidgetTester tester) async {
    int calls = 0;
    final TestHarness h = TestHarness(
      cache: InMemoryDigestCache(),
      server: (http.Request r) {
        calls++;
        throw http.ClientException('Failed host lookup');
      },
    );
    await pumpSidesApp(tester, harness: h);

    expect(find.text('You\'re offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(FakeAdsService.bannerKey), findsNothing,
        reason: 'no ads before there is content');
    expect(calls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('offline with a stale cache: cache shown with an offline note',
      (WidgetTester tester) async {
    final TestHarness h = TestHarness(
      cache: InMemoryDigestCache(
        CachedDigest(
          body: sampleDigestBody(),
          fetchedAt: sampleNow.subtract(const Duration(hours: 8)),
          etag: '"v1"',
        ),
      ),
      server: (http.Request r) => throw http.ClientException('offline'),
    );
    await pumpSidesApp(tester, harness: h);
    expect(h.requests, hasLength(1));
    expect(find.text(digest.stories.first.title), findsOneWidget);
    expect(find.textContaining('Showing the digest saved on this phone'),
        findsOneWidget);
  });

  testWidgets('tapping a story opens its detail page',
      (WidgetTester tester) async {
    await pumpSidesApp(tester);
    await tester.tap(find.text(digest.stories.first.title));
    await tester.pumpAndSettle();
    expect(find.text('1 of ${digest.stories.length}'), findsOneWidget);
    expect(find.text('Political lean'), findsWidgets);
  });

  testWidgets('reflows at 200% text size without overflow',
      (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSidesApp(tester);
    expect(tester.takeException(), isNull);
    // At 200% the date header and intro fill the first screen.
    await tester.scrollUntilVisible(
      find.text(digest.stories.first.title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(digest.stories.first.title));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
