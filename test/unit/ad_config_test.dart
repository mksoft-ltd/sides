import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:sides/core/config/ad_config.dart';

void main() {
  group('m3: ad request configuration', () {
    test('max ad content rating is T; not child-directed; age tag unset', () {
      final RequestConfiguration c = AdConfig.requestConfiguration;
      expect(c.maxAdContentRating, 'T');
      expect(c.maxAdContentRating, MaxAdContentRating.t);
      expect(c.tagForChildDirectedTreatment, TagForChildDirectedTreatment.no);
      expect(c.tagForUnderAgeOfConsent, isNull,
          reason: '"no" would claim no user is under the age of consent');
    });

    test('banner requests stay non-personalised', () {
      expect(AdConfig.bannerRequest.nonPersonalizedAds, isTrue);
    });

    test('the configuration is applied before the SDK initialises and the '
        'banner uses the shared request', () {
      final String src = File(
        'lib/features/ads/data/ads_service.dart',
      ).readAsStringSync();
      final int apply = src.indexOf(
        '.updateRequestConfiguration(AdConfig.requestConfiguration)',
      );
      final int init = src.indexOf('MobileAds.instance.initialize()');
      expect(apply, greaterThan(-1));
      expect(init, greaterThan(apply));
      expect(src, contains('request: AdConfig.bannerRequest,'));
      expect(
        src,
        isNot(contains('AdRequest(')),
        reason: 'every request goes through AdConfig.bannerRequest',
      );
    });
  });

  group('m4: release guard on test ad units', () {
    test('a release build with test units may not start ads', () {
      expect(AdConfig.mayStartAds(releaseMode: true, liveIds: false), isFalse);
      expect(AdConfig.mayStartAds(releaseMode: true, liveIds: true), isTrue);
      expect(AdConfig.mayStartAds(releaseMode: false, liveIds: false), isTrue);
    });

    test(
      'liveIdsConfigured is false while the release units are test units',
      () {
        expect(AdConfig.liveIdsConfigured, isFalse);
        expect(
          AdConfig.mayStartAds(releaseMode: true),
          isFalse,
          reason: 'today a release build must start without ads',
        );
      },
    );
  });
}
