import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';
import 'package:sides/features/settings/presentation/providers/settings_controller.dart';

import 'package:sides/features/digest/domain/digest.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  group('m6: "Ad privacy options" waits for UMP consent', () {
    // Tall surface: the settings list builds every tile, so "absent" means
    // absent, not "not built yet".
    const Size tall = Size(390, 3000);
    const String tile = 'Ad privacy options';

    testWidgets('hidden until consent is gathered, then shown when required',
        (WidgetTester tester) async {
      final TestHarness h = TestHarness()..ads.privacyRequired = true;
      await pumpSidesApp(tester,
          harness: h, initialLocation: '/settings', size: tall);
      expect(find.text(tile), findsNothing,
          reason: 'before UMP answers, the status is unknown');

      h.ads.consent.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(tile), findsOneWidget);
    });

    testWidgets('stays hidden when consent gathering failed',
        (WidgetTester tester) async {
      final TestHarness h = TestHarness()..ads.privacyRequired = true;
      await pumpSidesApp(tester,
          harness: h, initialLocation: '/settings', size: tall);
      h.ads.consent.complete(false);
      await tester.pumpAndSettle();
      expect(find.text(tile), findsNothing);
    });

    testWidgets('stays hidden when UMP says it is not required',
        (WidgetTester tester) async {
      final TestHarness h = TestHarness();
      await pumpSidesApp(tester,
          harness: h, initialLocation: '/settings', size: tall);
      h.ads.consent.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(tile), findsNothing);
    });
  });

  group('About: publisher and contact (Play News apps policy)', () {
    const Size tall = Size(390, 3000);

    testWidgets('shows publisher, contact address and privacy policy',
        (WidgetTester tester) async {
      await pumpSidesApp(tester, initialLocation: '/settings', size: tall);
      expect(find.text(Copy.publishedBy), findsOneWidget);
      expect(find.text(Copy.contact), findsOneWidget);
      expect(find.text('info@froggyeye.com'), findsOneWidget);
      expect(find.text(Copy.privacyPolicy), findsOneWidget);
    });

    testWidgets('contact tap composes a mailto to the publisher',
        (WidgetTester tester) async {
      final TestHarness h = await pumpSidesApp(tester,
          initialLocation: '/settings', size: tall);
      await tester.tap(find.text(Copy.contact));
      await tester.pumpAndSettle();
      expect(h.launcher.composed.single.toString(),
          'mailto:info@froggyeye.com');
      expect(h.launcher.opened, isEmpty,
          reason: 'mail must not go through the http/https article path');
      expect(find.text(Copy.contactFailed), findsNothing);
    });

    testWidgets('contact tap with no mail app shows the address',
        (WidgetTester tester) async {
      final TestHarness h = TestHarness()..launcher.result = false;
      await pumpSidesApp(tester,
          harness: h, initialLocation: '/settings', size: tall);
      await tester.tap(find.text(Copy.contact));
      await tester.pumpAndSettle();
      expect(find.text(Copy.contactFailed), findsOneWidget);
    });

    testWidgets('privacy tap opens the privacy policy URL',
        (WidgetTester tester) async {
      final TestHarness h = await pumpSidesApp(tester,
          initialLocation: '/settings', size: tall);
      await tester.tap(find.text(Copy.privacyPolicy));
      await tester.pumpAndSettle();
      expect(h.launcher.opened.single.toString(), AppConfig.privacyPolicyUrl);
      expect(h.launcher.composed, isEmpty);
    });
  });

  testWidgets('settings: theme, ad-free with store price, about',
      (WidgetTester tester) async {
    final TestHarness h = await pumpSidesApp(tester, initialLocation: '/settings');
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Remove ads — £2.99'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(h.settings.getString(ThemeModeController.key), 'dark');
    expect(
      Theme.of(tester.element(find.text('Settings').first)).brightness,
      Brightness.dark,
    );

    await tester.scrollUntilVisible(find.text(AppConfig.copyright), 300);
    expect(find.text(AppConfig.copyright), findsOneWidget);
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(h.launcher.opened.single.toString(), AppConfig.privacyPolicyUrl);
  });

  testWidgets('buying hides the banner instantly and thanks the user',
      (WidgetTester tester) async {
    final TestHarness h = await pumpSidesApp(tester);
    expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove ads — £2.99'));
    await tester.pump();
    expect(h.store.buyCalls, 1);

    h.store.emit(FakeStoreGateway.purchase(
        AppConfig.adFreeProductId, PurchaseStatus.purchased));
    await tester.pumpAndSettle();
    expect(find.text('Ad-free unlocked'), findsOneWidget);
    expect(find.textContaining('Ads removed'), findsOneWidget);
    expect(h.settings.getBool(AdFreeController.ownedKey), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
  });

  testWidgets('cancelling the sheet re-enables the button',
      (WidgetTester tester) async {
    final TestHarness h = await pumpSidesApp(tester, initialLocation: '/settings');
    await tester.tap(find.text('Remove ads — £2.99'));
    await tester.pump();
    expect(find.text('Working…'), findsOneWidget);
    h.store.emit(FakeStoreGateway.purchase(
        AppConfig.adFreeProductId, PurchaseStatus.canceled));
    await tester.pumpAndSettle();
    expect(find.text('Remove ads — £2.99'), findsOneWidget);
    expect(find.textContaining('Purchase cancelled'), findsOneWidget);
  });

  testWidgets('outlet list shows ratings basis and state media tags',
      (WidgetTester tester) async {
    await pumpSidesApp(tester, initialLocation: '/settings/outlets');
    expect(find.text('Western outlets'), findsOneWidget);
    expect(find.textContaining('AllSides'), findsWidgets);
    final Outlet state =
        sampleDigest().outlets.firstWhere((Outlet o) => o.isStateControlled);
    final Finder name = find.text('${state.name} · ${state.country}');
    await tester.scrollUntilVisible(name, 300);
    final Finder entry = find.ancestor(of: name, matching: find.byType(Column)).first;
    expect(find.descendant(of: entry, matching: find.text('state media')),
        findsOneWidget);
  });
}
