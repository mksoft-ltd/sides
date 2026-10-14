/// Compile-time and product constants. Nothing here is a secret: the app
/// talks only to a public JSON file and the two stores.
abstract final class AppConfig {
  static const String appName = 'Sides';
  static const String appTagline = 'The News, Every Angle';

  /// The daily digest, published by the pipeline to GitHub Pages.
  static const String digestUrl =
      'https://mksoft-ltd.github.io/sides/digest/latest.json';

  static const String privacyPolicyUrl =
      'https://mksoft-ltd.github.io/sides/privacy_policy.html';

  static const String copyright = '© 2026 Froggy Eye Ltd';

  /// Non-consumable that removes the banner ads (house-facts §4).
  static const String adFreeProductId = 'com.froggyeye.sides.adfree';

  /// The only digest schema this build understands.
  static const int supportedSchemaVersion = 1;

  /// Revalidate a cached digest once it is older than this, even if its
  /// date is today (the pipeline may republish after a failed run).
  static const Duration maxCacheAge = Duration(hours: 6);

  static const Duration fetchTimeout = Duration(seconds: 20);

  /// `--dart-define=SCREENSHOT_MODE=true` seeds the bundled sample digest so
  /// the store screenshot harness has stable, attractive content. Ignored in
  /// release builds (see [DigestSourceMode]).
  static const bool screenshotMode =
      bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false);

  static const String sampleDigestAsset = 'assets/sample_digest.json';
}
