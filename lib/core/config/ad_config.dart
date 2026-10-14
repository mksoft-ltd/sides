import 'package:flutter/foundation.dart';

/// Every AdMob identifier the app uses, in one place.
///
/// Debug and profile builds must only ever request Google's official test
/// units: debug impressions on live units count as invalid traffic and put
/// the whole publisher account at risk. The live unit IDs are created in the
/// AdMob console at the publish stage and go into [_releaseBannerAndroid] /
/// [_releaseBannerIos], together with the GADApplicationIdentifier in
/// ios/Runner/Info.plist and the APPLICATION_ID meta-data in
/// android/app/src/main/AndroidManifest.xml (both currently Google's test
/// app IDs).
abstract final class AdConfig {
  // Google's published test units for anchored adaptive banners.
  static const String testBannerAndroid =
      'ca-app-pub-3940256099942544/9214589741';
  static const String testBannerIos = 'ca-app-pub-3940256099942544/2435281174';

  // Publish stage: replace with the live units. Until then release builds
  // also serve test ads, which is safe (they earn nothing) and visible.
  static const String _releaseBannerAndroid = testBannerAndroid;
  static const String _releaseBannerIos = testBannerIos;

  /// Whether live IDs have been filled in. The release checklist reads this.
  static const bool liveIdsConfigured = false;

  static String bannerUnitId(TargetPlatform platform) {
    const bool live = kReleaseMode;
    return switch (platform) {
      TargetPlatform.iOS => live ? _releaseBannerIos : testBannerIos,
      _ => live ? _releaseBannerAndroid : testBannerAndroid,
    };
  }
}
