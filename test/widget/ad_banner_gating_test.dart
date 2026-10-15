import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/presentation/screens/master_detail_screen.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// The banner is the one paid surface; the ad-free unlock must remove it on
/// every path that grants it (buy, restore) and on none that do not
/// (pending, cancel, error). And no banner before there is content.
void main() {
  const Size tablet = Size(1366, 1024);
  final Finder banner = find.byKey(FakeAdsService.bannerKey);

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  PurchaseDetails adFree(PurchaseStatus s, {String? error}) =>
      FakeStoreGateway.purchase(
        AppConfig.adFreeProductId,
        s,
        errorMessage: error,
      );

  testWidgets('restore on phone: banner gone on the list and the story page', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness();
    h.store.owned = <PurchaseDetails>[adFree(PurchaseStatus.purchased)];
    await pumpSidesApp(tester, harness: h);
    expect(banner, findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('Restore purchases'));
    await tester.pump();
    // Restore listens for a fixed window before reporting.
    await tester.pump(AdFreeController.restoreWindow);
    await tester.pumpAndSettle();
    expect(find.text('Ad-free unlocked'), findsOneWidget);
    expect(h.settings.getBool(AdFreeController.ownedKey), isTrue);

    await back(tester);
    expect(banner, findsNothing);
    await tester.tap(find.text(sampleDigest().stories.first.title));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('restore on tablet: banner gone from under the detail pane', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness();
    h.store.owned = <PurchaseDetails>[adFree(PurchaseStatus.restored)];
    await pumpSidesApp(tester, harness: h, size: tablet);
    expect(
      find.descendant(
        of: find.byKey(MasterDetailScreen.detailPaneKey),
        matching: banner,
      ),
      findsOneWidget,
    );

    await openSettings(tester);
    await tester.tap(find.text('Restore purchases'));
    await tester.pump();
    await tester.pump(AdFreeController.restoreWindow);
    await tester.pumpAndSettle();
    await back(tester);
    expect(banner, findsNothing);
  });

  testWidgets('a purchase delivered while on the list hides it immediately', (
    WidgetTester tester,
  ) async {
    final TestHarness h = await pumpSidesApp(tester);
    expect(banner, findsOneWidget);
    h.store.emit(adFree(PurchaseStatus.purchased));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  final Map<String, PurchaseDetails Function()> notGranted =
      <String, PurchaseDetails Function()>{
        'pending (Ask to Buy / slow card)': () =>
            adFree(PurchaseStatus.pending),
        'cancelled': () => adFree(PurchaseStatus.canceled),
        'store error': () =>
            adFree(PurchaseStatus.error, error: 'BillingResponse.error'),
        'another product': () => FakeStoreGateway.purchase(
          'com.froggyeye.sides.other',
          PurchaseStatus.purchased,
        ),
      };

  for (final MapEntry<String, PurchaseDetails Function()> e
      in notGranted.entries) {
    testWidgets('${e.key}: the banner stays and nothing is persisted', (
      WidgetTester tester,
    ) async {
      final TestHarness h = await pumpSidesApp(tester);
      await openSettings(tester);
      await tester.tap(find.text('Remove ads — £2.99'));
      await tester.pump();
      h.store.emit(e.value());
      await tester.pumpAndSettle();
      if (e.key != 'another product') {
        // (A stray product leaves `busy` to the 75 s ceiling; Sides sells
        // one product, so that is accepted rather than tested.)
        expect(
          find.text('Remove ads — £2.99'),
          findsOneWidget,
          reason: 'the buy button is usable again',
        );
      }
      expect(h.settings.getBool(AdFreeController.ownedKey), isNot(true));
      await back(tester);
      expect(banner, findsOneWidget);
    });
  }

  testWidgets('no banner while there is no digest (offline, no cache)', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness(
      cache: InMemoryDigestCache(),
      server: (http.Request _) => throw http.ClientException('offline'),
    );
    await pumpSidesApp(tester, harness: h);
    expect(find.text('Retry'), findsOneWidget);
    expect(banner, findsNothing);
    expect(h.ads.bannersBuilt, 0);
  });

  testWidgets('no banner on tablet while there is no digest', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness(
      cache: InMemoryDigestCache(),
      server: (http.Request _) => throw http.ClientException('offline'),
    );
    await pumpSidesApp(tester, harness: h, size: tablet);
    expect(banner, findsNothing);
  });

  testWidgets('no banner on a story page for a story not in the digest', (
    WidgetTester tester,
  ) async {
    await pumpSidesApp(tester, initialLocation: '/story/000000000000');
    expect(find.text('Story not available'), findsOneWidget);
    expect(banner, findsNothing);
  });

  testWidgets('a cached unlock means no banner is ever built', (
    WidgetTester tester,
  ) async {
    final TestHarness h = TestHarness(adFree: true);
    await pumpSidesApp(tester, harness: h);
    await tester.tap(find.text(sampleDigest().stories.first.title));
    await tester.pumpAndSettle();
    expect(h.ads.bannersBuilt, 0);
  });

  testWidgets('a cached unlock with the cache freshly fetched builds no ad '
      'on tablet either', (WidgetTester tester) async {
    final TestHarness h = TestHarness(
      adFree: true,
      cache: InMemoryDigestCache(
        CachedDigest(body: sampleDigestBody(), fetchedAt: sampleNow),
      ),
    );
    await pumpSidesApp(tester, harness: h, size: tablet);
    expect(h.ads.bannersBuilt, 0);
  });
}
