import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sides/core/config/app_config.dart';

/// Guards that only matter in a release build, which `flutter test` (debug)
/// cannot exercise. A behavioural check like
/// `expect(useSample, isFalse)` passes in debug even with the release floor
/// deleted, so these read the source text instead, and pin the literals the
/// stores and the pipeline depend on so a drift fails loudly.
void main() {
  final String mainSrc = File('lib/main.dart').readAsStringSync();

  test('the bundled sample can never replace the network in release', () {
    expect(
      mainSrc,
      contains(
        'const bool useSample = !kReleaseMode && AppConfig.screenshotMode;',
      ),
    );
    // The sample repository is only built under that flag.
    expect(
      RegExp(r'useSample\s*\?\s*BundledDigestRepository').hasMatch(mainSrc),
      isTrue,
    );
    expect(mainSrc, contains('useSample ? AppConfig.screenshotRoute'));
  });

  test('screenshot mode switches real ads off rather than on', () {
    expect(mainSrc, contains('if (mobile && !useSample)'));
  });

  test('orientation overrides apply only to the screenshot harness', () {
    final int guard = mainSrc.indexOf('if (useSample) {');
    final int rotate = mainSrc.indexOf('setPreferredOrientations');
    expect(guard, greaterThan(-1));
    expect(rotate, greaterThan(guard));
  });

  test('the screenshot defines default off', () {
    expect(
      AppConfig.screenshotMode,
      isFalse,
      reason: 'flutter test runs without --dart-define',
    );
    expect(AppConfig.screenshotRoute, '/');
  });

  test('store and pipeline contract literals', () {
    expect(AppConfig.adFreeProductId, 'com.froggyeye.sides.adfree');
    expect(
      AppConfig.digestUrl,
      'https://mksoft-ltd.github.io/sides/digest/latest.json',
    );
    expect(
      AppConfig.privacyPolicyUrl,
      'https://mksoft-ltd.github.io/sides/privacy_policy.html',
    );
    expect(AppConfig.supportedSchemaVersion, 1);
    expect(AppConfig.maxCacheAge, const Duration(hours: 6));
  });

  test('the sample asset ships (it backs debug preview and screenshots)', () {
    expect(File(AppConfig.sampleDigestAsset).existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- ${AppConfig.sampleDigestAsset}'),
    );
  });
}
