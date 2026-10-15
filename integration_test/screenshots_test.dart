import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sides/app/app.dart';
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
import 'package:sides/features/settings/presentation/providers/settings_controller.dart';
import 'package:sides/features/story/presentation/widgets/story_detail_view.dart';

/// Store-screenshot harness. Shot names are the `raw` names in
/// `store_assets/screenshots/specs.json` (and `screenshot_specs.md`), so the
/// framer (`store_assets/screenshots/render.sh`) reads the captures as-is.
///
/// Each shot pumps the real app afresh at its own route on the bundled sample
/// digest (`assets/sample_digest.json`, the 14 Oct 2026 run) with every seam
/// overridden: no network, no ads SDK, no StoreKit/Play Billing, no
/// SharedPreferences. The theme is forced per shot through the settings store.
///
/// The device decides the set: < 744 dp wide = the six `phone_*` shots plus
/// `iap_review_settings` (the App Store IAP review screenshot); >= 744 dp =
/// the four `ipad_*` shots (landscape, so the >= 1100 dp column layout shows).
///
/// Capture, never run by hand (both scripts check count, size and md5):
///   iOS:     scripts/publish/capture_ios.py   (host-side `simctl io`; the
///            in-app `takeScreenshot` returns the launch screen on iOS sims)
///   Android: scripts/publish/capture_android.sh (`takeScreenshot` through
///            test_driver/integration_test.dart into `SCREENSHOT_DIR`)
///
/// iOS host mode (`--dart-define=SCREENSHOT_HOST_DIR=<dir>`): at each shot the
/// test prints `SIDES_SHOT_READY <name>`, keeps pumping frames, and waits for
/// the host to create `<dir>/<name>.done` after grabbing the simulator screen.
///
/// `--dart-define=SCREENSHOT_PRICE=£2.99` sets the localised price on the
/// settings shot (default £2.99, the UK storefront the IAP is priced in).
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String price = String.fromEnvironment(
    'SCREENSHOT_PRICE',
    defaultValue: '£2.99',
  );
  const String hostDir = String.fromEnvironment('SCREENSHOT_HOST_DIR');

  bool surfaceConverted = false;
  final List<String> shots = <String>[];

  /// Fixed-step pumps: settling would wait on the RefreshIndicator and the
  /// ink splashes, and a never-idle tree hangs a harness instead of failing.
  Future<void> settle(WidgetTester tester, [int frames = 15]) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  void require(Finder finder, String what) {
    if (finder.evaluate().isEmpty) {
      fail(
        'Screenshot harness could not find $what. The UI it keys off has '
        'changed; update integration_test/screenshots_test.dart with it.',
      );
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester, 10);
    if (hostDir.isNotEmpty) {
      final File done = File('$hostDir/$name.done');
      if (done.existsSync()) done.deleteSync();
      // ignore: avoid_print
      print('SIDES_SHOT_READY $name');
      final DateTime until = DateTime.now().add(const Duration(seconds: 60));
      while (!done.existsSync()) {
        if (DateTime.now().isAfter(until)) {
          fail('host never captured $name (no $hostDir/$name.done)');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    } else {
      if (Platform.isAndroid && !surfaceConverted) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      await tester.pump();
      await binding.takeScreenshot(name);
    }
    shots.add(name);
  }

  Future<void> launch(
    WidgetTester tester,
    String route,
    ThemeMode theme,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(<String, Object>{
              ThemeModeController.key: theme.name,
            }),
          ),
          digestRepositoryProvider.overrideWithValue(
            BundledDigestRepository(bundle: rootBundle),
          ),
          storeGatewayProvider.overrideWithValue(_ScreenshotStore(price)),
          reconcileAtLaunchProvider.overrideWithValue(false),
          adsServiceProvider.overrideWithValue(const DisabledAdsService()),
          linkLauncherProvider.overrideWithValue(_NoLaunch()),
        ],
        child: SidesApp(key: UniqueKey(), initialLocation: route),
      ),
    );
    await settle(tester, 30);
    require(find.byType(SidesApp), 'the app');
  }

  Finder detailScrollable() => find
      .descendant(
        of: find.byType(StoryDetailView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the story page until [target] sits [below] dp under the top of
  /// the story's scroll viewport (just under the app bar on phones).
  Future<void> scrollTo(
    WidgetTester tester,
    Finder target, {
    double below = 120,
  }) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: detailScrollable(),
    );
    await Scrollable.ensureVisible(tester.element(target.first));
    await settle(tester);
    final ScrollableState s = tester.state<ScrollableState>(detailScrollable());
    final double top = tester.getTopLeft(detailScrollable()).dy;
    final double at = tester.getTopLeft(target.first).dy;
    final double want = (s.position.pixels + (at - top) - below).clamp(
      s.position.minScrollExtent,
      s.position.maxScrollExtent,
    );
    s.position.jumpTo(want);
    await settle(tester);
    require(target.hitTestable(), 'the scroll anchor on screen');
  }

  const String leanStory = '/story/c8bbc1a001c2';
  const String blocStory = '/story/8c5fe1c3c5b6?axis=bloc';
  const String blindspotStory = '/story/b4b715a72e0d';
  const String agreedStory = '/story/aa7201957adf';
  const String sourcesStory = '/story/728984a49b5c';
  final Finder blindspotChip = find.text(
    'Only left-leaning outlets covered this',
  );
  final Finder sourcesHeader = find.textContaining('${Copy.sources} (');

  testWidgets('store screenshots on the sample digest', (
    WidgetTester tester,
  ) async {
    // Tablets are captured in landscape (the >= 1100 dp column layout).
    final Size dp = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (dp.shortestSide >= 600) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await launch(tester, '/', ThemeMode.light);
    final LayoutSize layout = LayoutSize.of(
      tester.element(find.byType(Scaffold).first),
    );
    final bool tablet = layout != LayoutSize.compact;
    // ignore: avoid_print
    print(
      'screenshots: ${tester.view.physicalSize / tester.view.devicePixelRatio}'
      ' dp -> $layout',
    );

    if (!tablet) {
      require(
        find.textContaining('Last updated').hitTestable(),
        'the digest header',
      );
      require(find.textContaining('Pope Leo'), 'story 1 in the list');
      await shoot(tester, 'phone_01_digest');

      await launch(tester, leanStory, ThemeMode.light);
      require(find.widgetWithText(Tab, 'Left'), 'the Left tab');
      await shoot(tester, 'phone_02_wording');

      await launch(tester, blocStory, ThemeMode.dark);
      require(find.widgetWithText(Tab, 'West'), 'the West tab');
      await shoot(tester, 'phone_03_west_east');

      await launch(tester, blindspotStory, ThemeMode.light);
      require(
        blindspotChip.hitTestable(),
        'the left-only blindspot chip on screen',
      );
      await shoot(tester, 'phone_04_blindspot');

      await launch(tester, agreedStory, ThemeMode.light);
      await scrollTo(tester, find.text(Copy.agreed));
      await shoot(tester, 'phone_05_agreed');

      await launch(tester, sourcesStory, ThemeMode.dark);
      await scrollTo(tester, sourcesHeader);
      await shoot(tester, 'phone_06_sources');

      await launch(tester, '/settings', ThemeMode.light);
      require(
        find.text('Remove ads — $price').hitTestable(),
        'the ad-free price button',
      );
      await shoot(tester, 'iap_review_settings');
      expect(shots, hasLength(7));
    } else {
      require(
        find.byKey(MasterDetailScreen.detailPaneKey),
        'the tablet detail pane',
      );
      if (layout != LayoutSize.expanded) {
        fail(
          'tablet shots need the >= 1100 dp column layout (landscape); got $layout',
        );
      }
      await launch(tester, leanStory, ThemeMode.light);
      require(find.byKey(PerspectiveColumns.keyFor('left')), 'the Left column');
      await shoot(tester, 'ipad_01_lean_columns');

      await launch(tester, blocStory, ThemeMode.dark);
      require(find.byKey(PerspectiveColumns.keyFor('east')), 'the East column');
      await shoot(tester, 'ipad_02_bloc_dark');

      await launch(tester, blindspotStory, ThemeMode.light);
      require(
        find
            .descendant(
              of: find.byKey(MasterDetailScreen.detailPaneKey),
              matching: blindspotChip,
            )
            .hitTestable(),
        'the blindspot chip in the detail pane',
      );
      await shoot(tester, 'ipad_03_blindspot');

      await launch(tester, sourcesStory, ThemeMode.light);
      await scrollTo(tester, sourcesHeader, below: 80);
      await shoot(tester, 'ipad_04_sources');
      expect(shots, hasLength(4));
    }
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
