import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sides/app/app.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/core/constants/copy.dart';
import 'package:sides/core/launcher/link_launcher.dart';
import 'package:sides/core/layout/breakpoints.dart';
import 'package:sides/core/storage/settings_store.dart';
import 'package:sides/features/ads/data/ads_service.dart';
import 'package:sides/features/digest/data/digest_repository.dart';
import 'package:sides/features/digest/presentation/providers/digest_controller.dart';
import 'package:sides/features/digest/presentation/screens/master_detail_screen.dart';
import 'package:sides/features/purchases/data/store_gateway.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

/// Store-screenshot harness and on-device journey test.
///
/// Runs the real app on the bundled sample digest (`assets/sample_digest.json`,
/// the real 14 Oct 2026 run) with every seam overridden, so no network, no
/// ads SDK, no StoreKit/Play Billing and no SharedPreferences are touched. It
/// is the same composition `main()` uses for `SCREENSHOT_MODE=true`, minus the
/// native store gateway.
///
/// Journey check on a simulator (no PNGs written):
///
///   flutter test integration_test/screenshots_test.dart -d DEVICE_ID
///
/// Store captures (the driver writes PNGs to `SCREENSHOT_DIR`, default
/// `store_assets/screenshots/raw/DEVICE`; set it per device so a second run
/// does not overwrite the first):
///
///   SCREENSHOT_DIR=store_assets/screenshots/raw/iphone_69 \
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart -d DEVICE_ID \
///     [--dart-define=SCREENSHOT_PRICE=£2.99]
///
/// Shots, in marketing order (no docs/ASO.md yet; reorder here when it lands):
///   phone  (< 744 dp): 01_list, 02_story_lean, 03_story_west_east,
///                      04_sources, 05_settings
///   tablet (>= 744 dp): 01_master_detail, 02_story_lean (columns at
///                      >= 1100 dp), 03_story_west_east, 04_sources,
///                      05_settings
///
/// Always `md5` the PNGs afterwards: on some iOS simulator builds
/// `takeScreenshot` returns the launch screen for every shot while every
/// assertion here passes (see docs/TEST_PLAN.md).
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The store's localised price is shown verbatim on the settings screen;
  /// pass the live tier's string when capturing for a given storefront.
  const String price = String.fromEnvironment(
    'SCREENSHOT_PRICE',
    defaultValue: '£2.99',
  );

  /// Story 5 (Sally Rooney, 3 Western / 4 Eastern outlets) makes the richest
  /// West / East shot in the sample; story 1 the richest lean shot.
  const String leanStoryId = 'c8bbc1a001c2';
  const String blocStoryId = '8c5fe1c3c5b6';

  // convertFlutterSurfaceToImage may run once per test (it asserts it has not
  // already run); it is Android-only.
  bool surfaceConverted = false;
  final List<String> shots = <String>[];

  /// Fixed-step pumps: settling would wait on the RefreshIndicator and the
  /// ink splashes, and a never-idle tree hangs a harness instead of failing.
  Future<void> settle(WidgetTester tester, [int frames = 15]) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await tester.pump();
    await binding.takeScreenshot(name);
    shots.add(name);
  }

  /// Fails with what it was looking for: this runs unattended in the
  /// publish stage, and "found 0 widgets" names nothing.
  void require(Finder finder, String what) {
    if (finder.evaluate().isEmpty) {
      fail(
        'Screenshot harness could not find $what. The UI it keys off has '
        'changed; update integration_test/screenshots_test.dart with it.',
      );
    }
  }

  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls [target] fully on screen before tapping: a tap on a widget
  /// that is built but off-screen only warns and silently misses.
  Future<void> tapOnScreen(
    WidgetTester tester,
    Finder target,
    Finder scrollable,
    String what,
  ) async {
    await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
    await tester.ensureVisible(target);
    await settle(tester);
    require(target.hitTestable(), '$what (on screen)');
    await tester.tap(target.hitTestable().first);
    await settle(tester);
  }

  /// Brings [target] in the story page on screen at [alignment] (0 = top,
  /// 1 = bottom). scrollUntilVisible alone stops once the target is built,
  /// which can be inside the cache extent below the screen.
  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    required double alignment,
  }) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: detailScrollable(),
    );
    await Scrollable.ensureVisible(
      tester.element(target.first),
      alignment: alignment,
    );
    await settle(tester);
  }

  Future<void> chooseAxis(WidgetTester tester, String label) async {
    final Finder f = find.descendant(
      of: find.byType(SegmentedButton<PerspectiveAxis>),
      matching: find.text(label),
    );
    require(f, 'the "$label" axis switch');
    await tester.tap(f);
    await settle(tester);
  }

  /// Back the way the system gesture goes, not by an icon (the chevron
  /// differs between iOS and Android).
  Future<void> goBack(WidgetTester tester) async {
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    if (nav.canPop()) nav.pop();
    await settle(tester);
  }

  testWidgets('journey + store screenshots on the sample digest', (
    WidgetTester tester,
  ) async {
    final _ScreenshotStore store = _ScreenshotStore(price);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          digestRepositoryProvider.overrideWithValue(
            BundledDigestRepository(bundle: rootBundle),
          ),
          storeGatewayProvider.overrideWithValue(store),
          reconcileAtLaunchProvider.overrideWithValue(false),
          adsServiceProvider.overrideWithValue(const DisabledAdsService()),
          linkLauncherProvider.overrideWithValue(_NoLaunch()),
        ],
        child: const SidesApp(),
      ),
    );
    await settle(tester, 30);

    final LayoutSize layout = LayoutSize.of(
      tester.element(find.byType(Scaffold).first),
    );
    final bool tablet = layout != LayoutSize.compact;
    debugPrint(
      'screenshots: ${tester.view.physicalSize / tester.view.devicePixelRatio}'
      ' dp → $layout',
    );

    // ---- 01: the digest (list, or list + story 1 on tablets) -------------
    require(
      find.textContaining('Last updated').hitTestable(),
      'the digest header',
    );
    final Finder storyOne = find.textContaining('Pope Leo');
    require(storyOne, 'story 1 in the list');
    if (tablet) {
      require(
        find.byKey(MasterDetailScreen.detailPaneKey),
        'the tablet detail pane',
      );
      await shoot(tester, '01_master_detail');
    } else {
      await shoot(tester, '01_list');
      await tester.tap(storyOne.first);
      await settle(tester);
    }

    // ---- 02: story 1 by political lean --------------------------------------
    require(find.byType(StoryDetailView), 'the story page for story 1');
    if (layout == LayoutSize.expanded &&
        find.byType(PerspectiveColumns).evaluate().isNotEmpty) {
      require(find.byKey(PerspectiveColumns.keyFor('left')), 'the Left column');
    } else {
      require(find.widgetWithText(Tab, 'Left'), 'the Left tab');
    }
    // Phone: from the top (title, coverage, axis switch, tabs). Tablet: 01
    // already shows that, so show the shared sections instead.
    if (tablet) {
      await reveal(tester, find.text(Copy.agreed), alignment: 0.05);
    }
    await shoot(tester, '02_story_lean');

    // ---- 03: West / East on the story with the most Eastern coverage -------
    if (tablet) {
      await tapOnScreen(
        tester,
        find.descendant(
          of: find.byKey(MasterDetailScreen.listPaneKey),
          matching: find.textContaining('Sally Rooney'),
        ),
        find
            .descendant(
              of: find.byKey(MasterDetailScreen.listPaneKey),
              matching: find.byType(Scrollable),
            )
            .first,
        'story 5 in the list pane',
      );
    } else {
      await goBack(tester);
      await tapOnScreen(
        tester,
        find.textContaining('Sally Rooney'),
        find.byType(Scrollable).first,
        'story 5 in the list',
      );
    }
    require(
      find.descendant(
        of: find.byType(StoryDetailView),
        matching: find.textContaining('Sally Rooney'),
      ),
      'story 5 ($blocStoryId) in the detail view',
    );
    await chooseAxis(tester, Copy.axisBloc);
    if (find.byType(PerspectiveColumns).evaluate().isEmpty) {
      require(find.widgetWithText(Tab, 'East'), 'the East tab');
      await tester.tap(find.widgetWithText(Tab, 'East'));
      await settle(tester);
    } else {
      require(find.byKey(PerspectiveColumns.keyFor('east')), 'the East column');
    }
    // The axis switch and East tab at the top, East framing below it.
    await reveal(
      tester,
      find.byType(SegmentedButton<PerspectiveAxis>),
      alignment: 0.02,
    );
    await shoot(tester, '03_story_west_east');

    // ---- 04: every point is sourced (the story's Sources list) -------------
    final Finder sources = find.textContaining('${Copy.sources} (');
    await reveal(tester, sources, alignment: 0.05);
    require(sources.hitTestable(), 'the Sources header on screen');
    await shoot(tester, '04_sources');

    // ---- 05: settings (ad-free, how it works) -------------------------------
    if (!tablet) await goBack(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    require(find.text('Settings'), 'the Settings screen');
    require(find.text('Remove ads — $price'), 'the ad-free price button');
    await shoot(tester, '05_settings');
    await goBack(tester);

    expect(shots, hasLength(5));
    expect(find.byType(SidesApp), findsOneWidget);
    expect(leanStoryId, isNotEmpty);
    // The harness's own guarantees: nothing left the device.
    expect(store.buyCalls, 0);
    expect(AppConfig.digestUrl, startsWith('https://'));
  });
}

/// Never touches StoreKit or Play Billing: one product, priced from
/// SCREENSHOT_PRICE, nothing owned.
class _ScreenshotStore implements StoreGateway {
  _ScreenshotStore(this.price);
  final String price;
  int buyCalls = 0;
  final StreamController<List<PurchaseDetails>> _stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: <ProductDetails>[
          for (final String id in ids)
            ProductDetails(
              id: id,
              title: 'Remove ads',
              description: 'Removes banner ads',
              price: price,
              rawPrice: 0,
              currencyCode: 'GBP',
            ),
        ],
        notFoundIDs: const <String>[],
      );
  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    buyCalls++;
    return false;
  }

  @override
  Future<void> restorePurchases() async {}
  @override
  Future<void> completePurchase(PurchaseDetails details) async {}
}

class _NoLaunch implements LinkLauncher {
  @override
  Future<bool> open(Uri uri) async => false;
  @override
  Future<bool> compose(Uri mailto) async => false;
}
