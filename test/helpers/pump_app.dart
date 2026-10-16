import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sides/app/app.dart';
import 'package:sides/core/launcher/link_launcher.dart';
import 'package:sides/core/storage/settings_store.dart';
import 'package:sides/features/ads/data/ads_service.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/data/digest_remote.dart';
import 'package:sides/features/digest/data/digest_repository.dart';
import 'package:sides/features/digest/presentation/providers/digest_controller.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';
import 'package:sides/features/search/presentation/search_controller.dart';

import '../fixtures/fixtures.dart';
import 'fakes.dart';

/// Phone size from the brief: 390×844 logical pixels.
const Size phoneSize = Size(390, 844);

/// Everything a widget test needs to observe, all fakes, no plugins.
class TestHarness {
  TestHarness({
    InMemoryDigestCache? cache,
    http.Response Function(http.Request)? server,
    bool adFree = false,
  })  : cache = cache ?? freshCache(),
        settings = InMemorySettingsStore(<String, Object>{
          if (adFree) AdFreeController.ownedKey: true,
        }),
        _server = server ?? ((http.Request _) => http.Response('', 304));

  final InMemoryDigestCache cache;
  final InMemorySettingsStore settings;
  final http.Response Function(http.Request) _server;
  final FakeLinkLauncher launcher = FakeLinkLauncher();
  final FakeArchiveRepository archive = FakeArchiveRepository();
  final FakeTopicRepository topic = FakeTopicRepository();
  final FakeAdsService ads = FakeAdsService();
  final FakeStoreGateway store = FakeStoreGateway();
  final List<http.Request> requests = <http.Request>[];

  /// The sample digest, cached 15 minutes before [sampleNow]: no refetch.
  static InMemoryDigestCache freshCache() => InMemoryDigestCache(
        CachedDigest(
          body: sampleDigestBody(),
          fetchedAt: sampleNow.subtract(const Duration(minutes: 15)),
          etag: '"sample"',
        ),
      );

  List<Override> get overrides => <Override>[
        settingsStoreProvider.overrideWithValue(settings),
        digestRepositoryProvider.overrideWithValue(
          NetworkDigestRepository(
            cache: cache,
            remote: DigestRemote(
              client: MockClient((http.Request r) async {
                requests.add(r);
                return _server(r);
              }),
            ),
            clock: () => sampleNow,
            // Fake-async zone: a real isolate's reply would never arrive.
            parse: parseDigestInline,
          ),
        ),
        linkLauncherProvider.overrideWithValue(launcher),
        archiveRepositoryProvider.overrideWithValue(archive),
        topicRepositoryProvider.overrideWithValue(topic),
        adsServiceProvider.overrideWithValue(ads),
        storeGatewayProvider.overrideWithValue(store),
        reconcileAtLaunchProvider.overrideWithValue(false),
      ];
}

Future<TestHarness> pumpSidesApp(
  WidgetTester tester, {
  TestHarness? harness,
  String initialLocation = '/',
  Size size = phoneSize,
  /// False to stop after the first frame (to observe animations mid-way).
  bool settle = true,
}) async {
  final TestHarness h = harness ?? TestHarness();
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: SidesApp(initialLocation: initialLocation),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return h;
}
