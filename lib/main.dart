import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/config/ad_config.dart';
import 'core/config/app_config.dart';
import 'core/storage/settings_store.dart';
import 'features/ads/data/ads_service.dart';
import 'features/digest/data/digest_cache.dart';
import 'features/digest/data/digest_remote.dart';
import 'features/digest/data/digest_repository.dart';
import 'features/search/data/archive_repository.dart';
import 'features/search/data/topic_repository.dart';
import 'features/search/presentation/search_controller.dart';
import 'features/digest/presentation/providers/digest_controller.dart';
import 'features/purchases/data/store_gateway.dart';
import 'features/purchases/presentation/ad_free_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // The bundled sample digest stands in for the network only for the store
  // screenshot harness, and never in a release build.
  const bool useSample = !kReleaseMode && AppConfig.screenshotMode;
  if (useSample) {
    switch (AppConfig.screenshotOrientation) {
      case 'landscape':
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case 'portrait':
        await SystemChrome.setPreferredOrientations(
          <DeviceOrientation>[DeviceOrientation.portraitUp],
        );
    }
  }
  final DigestRepository repository = useSample
      ? BundledDigestRepository(bundle: rootBundle)
      : NetworkDigestRepository(
          cache: await FileDigestCache.open(),
          remote: DigestRemote(client: http.Client()),
        );

  final bool mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  // Release guard: never start the ads SDK on Google's test units in a
  // release build (AdConfig.mayStartAds). Debug says so once per launch.
  final bool adsAllowed = AdConfig.mayStartAds(releaseMode: kReleaseMode);
  if (kDebugMode && !AdConfig.liveIdsConfigured) {
    debugPrint('AdConfig: live AdMob IDs not configured; a release build '
        'would start without ads.');
  }

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider
            .overrideWithValue(SharedPreferencesSettingsStore(prefs)),
        digestRepositoryProvider.overrideWithValue(repository),
        archiveRepositoryProvider.overrideWithValue(
          NetworkArchiveRepository(
            client: http.Client(),
            cacheDir: useSample ? null : await archiveCacheDir(),
          ),
        ),
        topicRepositoryProvider.overrideWithValue(
          NetworkTopicRepository(client: http.Client()),
        ),
        storeGatewayProvider.overrideWithValue(NativeStoreGateway()),
        if (mobile && !useSample && adsAllowed)
          adsServiceProvider.overrideWithValue(AdMobAdsService()),
      ],
      child: const SidesApp(
        initialLocation: useSample ? AppConfig.screenshotRoute : '/',
      ),
    ),
  );
}

/// `<documents>/digest/archive`: past days the search downloaded.
Future<Directory> archiveCacheDir() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/digest/archive');
}
