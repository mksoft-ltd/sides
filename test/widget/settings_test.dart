import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';
import 'package:sides/features/settings/presentation/providers/settings_controller.dart';

import 'package:sides/features/digest/domain/digest.dart';

import '../fixtures/fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
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
