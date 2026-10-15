import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  // Live units (AdMob publisher pub-6255057925578575, created 15 Oct 2026).
  // Used only by release builds; debug and profile keep the test units above.
  static const String _releaseBannerAndroid =
      'ca-app-pub-6255057925578575/5017664516';
  static const String _releaseBannerIos =
      'ca-app-pub-6255057925578575/1517403205';

  /// Whether live IDs have been filled in. Derived from the unit IDs, so it
  /// cannot drift from them; [mayStartAds] reads it.
  static const bool liveIdsConfigured =
      _releaseBannerAndroid != testBannerAndroid &&
          _releaseBannerIos != testBannerIos;

  /// Release guard (compliance m4): a release build with Google's test units
  /// still in place does not initialise the Mobile Ads SDK at all, so a
  /// forgotten ID swap ships an ad-free build rather than test ads. Debug and
  /// profile builds always may (they only ever request test units).
  static bool mayStartAds({
    required bool releaseMode,
    bool liveIds = liveIdsConfigured,
  }) =>
      !releaseMode || liveIds;

  /// Applied once before the SDK initialises (compliance m3). Sides is rated
  /// 13+/Teen, so no ad above T; the app is not directed at children, so
  /// requests are tagged not child-directed. The under-age-of-consent tag is
  /// left unset on purpose: "no" would assert that no user is under the age
  /// of consent, which may be untrue for EEA readers aged 13-15.
  static RequestConfiguration get requestConfiguration => RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.t,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
      );

  /// Every banner request: non-personalised everywhere (no ATT, no IDFA).
  static const AdRequest bannerRequest = AdRequest(nonPersonalizedAds: true);

  static String bannerUnitId(TargetPlatform platform) {
    const bool live = kReleaseMode;
    return switch (platform) {
      TargetPlatform.iOS => live ? _releaseBannerIos : testBannerIos,
      _ => live ? _releaseBannerAndroid : testBannerAndroid,
    };
  }
}
