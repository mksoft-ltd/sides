import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/config/ad_config.dart';

/// Everything ad-related behind one seam, so widget tests never initialise
/// the Mobile Ads SDK or the consent SDK.
abstract class AdsService {
  /// Gathers consent (Google UMP, shown only where the law requires it) and
  /// initialises the SDK. Idempotent; banners await it before loading.
  Future<bool> initialize();

  /// Completes once Google UMP has been asked for this session's consent
  /// information: true when that succeeded (and any required form was
  /// shown), false when it failed. Never completes if ads never start.
  Future<bool> get consentGathered;

  /// Whether the user's region requires a "Privacy options" entry point.
  /// False until [consentGathered] has completed with true: before that UMP
  /// has no answer, and the entry must not appear (code review m6).
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();

  /// A self-managing banner for the bottom of a screen. Renders nothing
  /// until an ad has actually loaded, so there is never an empty gap.
  Widget banner();
}

/// No ads at all (tests, and builds where ads are unsupported).
class DisabledAdsService implements AdsService {
  const DisabledAdsService();
  @override
  Future<bool> initialize() async => false;
  @override
  Future<bool> get consentGathered async => false;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Widget banner() => const SizedBox.shrink();
}

/// AdMob, non-personalised everywhere.
///
/// No App Tracking Transparency prompt and no IDFA: Sides does not track
/// people (house convention shared with the sibling apps). Every request
/// carries `nonPersonalizedAds: true`, which is also what keeps iOS fill
/// alive without ATT authorisation.
class AdMobAdsService implements AdsService {
  Future<bool>? _ready;
  final Completer<bool> _consent = Completer<bool>();

  @override
  Future<bool> get consentGathered => _consent.future;

  @override
  Future<bool> initialize() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return false;
      await MobileAds.instance
          .updateRequestConfiguration(AdConfig.requestConfiguration);
      await MobileAds.instance.initialize();
      return true;
    } on Object catch (e) {
      debugPrint('Ads init failed: $e');
      if (!_consent.isCompleted) _consent.complete(false);
      return false;
    }
  }

  Future<void> _gatherConsent() {
    final Completer<void> done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((FormError? e) {
            if (e != null) debugPrint('UMP form: ${e.message}');
          });
        } on Object catch (e) {
          debugPrint('UMP form failed: $e');
        }
        if (!_consent.isCompleted) _consent.complete(true);
        if (!done.isCompleted) done.complete();
      },
      (FormError e) {
        debugPrint('UMP update failed: ${e.message}');
        if (!_consent.isCompleted) _consent.complete(false);
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    if (!_consent.isCompleted || !await _consent.future) return false;
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? e) {
        if (e != null) debugPrint('Privacy options: ${e.message}');
      });
    } on Object catch (e) {
      debugPrint('Privacy options failed: $e');
    }
  }

  @override
  Widget banner() => _AdMobBanner(service: this);
}

class _AdMobBanner extends StatefulWidget {
  const _AdMobBanner({required this.service});
  final AdMobAdsService service;

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final int width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      unawaited(_load(width));
    }
  }

  Future<void> _load(int width) async {
    if (!await widget.service.initialize() || !mounted) return;
    final AnchoredAdaptiveBannerAdSize? size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || width != _width) return;
    final TargetPlatform platform = Theme.of(context).platform;
    await _ad?.dispose();
    setState(() {
      _ad = null;
      _loaded = false;
    });
    final BannerAd ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId(platform),
      size: size,
      request: AdConfig.bannerRequest,
      listener: BannerAdListener(
        onAdLoaded: (Ad a) {
          if (!mounted) {
            a.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (Ad a, LoadAdError e) {
          debugPrint('Banner failed: ${e.message}');
          a.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BannerAd? ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}

/// Overridden in `main()` with [AdMobAdsService] on iOS/Android.
final Provider<AdsService> adsServiceProvider =
    Provider<AdsService>((Ref ref) => const DisabledAdsService());
