import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/storage/settings_store.dart';
import 'features/ads/data/ads_service.dart';
import 'features/digest/data/digest_cache.dart';
import 'features/digest/data/digest_remote.dart';
import 'features/digest/data/digest_repository.dart';
import 'features/digest/presentation/providers/digest_controller.dart';
import 'features/purchases/data/store_gateway.dart';
import 'features/purchases/presentation/ad_free_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // The bundled sample digest stands in for the network only for the store
  // screenshot harness, and never in a release build.
  const bool useSample = !kReleaseMode && AppConfig.screenshotMode;
  final DigestRepository repository = useSample
      ? BundledDigestRepository(bundle: rootBundle)
      : NetworkDigestRepository(
          cache: await FileDigestCache.open(),
          remote: DigestRemote(client: http.Client()),
        );

  final bool mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider
            .overrideWithValue(SharedPreferencesSettingsStore(prefs)),
        digestRepositoryProvider.overrideWithValue(repository),
        storeGatewayProvider.overrideWithValue(NativeStoreGateway()),
        if (mobile && !useSample)
          adsServiceProvider.overrideWithValue(AdMobAdsService()),
      ],
      child: const SidesApp(
        initialLocation: useSample ? AppConfig.screenshotRoute : '/',
      ),
    ),
  );
}
