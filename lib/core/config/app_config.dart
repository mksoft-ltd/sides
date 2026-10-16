/// Compile-time and product constants. Nothing here is a secret: the app
/// talks only to a public JSON file and the two stores.
abstract final class AppConfig {
  static const String appName = 'Sides';
  static const String appTagline = 'The News, Every Angle';

  /// The daily digest, published by the pipeline to GitHub Pages.
  static const String digestUrl =
      'https://mksoft-ltd.github.io/sides/digest/latest.json';

  /// The site root; the archive and the article pool live under it.
  static const String siteBase = 'https://mksoft-ltd.github.io/sides';
  static const String archiveIndexUrl = '$siteBase/digest/index.json';
  static String archiveDigestUrl(String date) => '$siteBase/digest/$date.json';

  /// The on-demand topic service (worker/): GET with `q=` the words. A new topic
  /// takes 30 to 90 seconds; a cached one answers at once.
  static const String topicUrl =
      'https://sides-topic.froggyeye.workers.dev/v1/topic';
  static const Duration topicTimeout = Duration(seconds: 150);

  static const String privacyPolicyUrl =
      'https://mksoft-ltd.github.io/sides/privacy_policy.html';

  static const String copyright = '© 2026 Froggy Eye Ltd';

  /// Publisher contact shown in Settings › About (Play News apps policy).
  static const String contactEmail = 'info@froggyeye.com';
  static final Uri contactMailto = Uri(scheme: 'mailto', path: contactEmail);

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

  /// Screenshot harness only: the route to open at launch, e.g.
  /// `/story/<id>?axis=bloc`. Ignored unless [screenshotMode] is on in a
  /// non-release build.
  static const String screenshotRoute =
      String.fromEnvironment('SCREENSHOT_ROUTE', defaultValue: '/');

  /// Screenshot harness only: `landscape` or `portrait` asks the system to
  /// rotate at launch (simulators without a GUI cannot be rotated by hand).
  /// Ignored unless [screenshotMode] is on in a non-release build.
  static const String screenshotOrientation =
      String.fromEnvironment('SCREENSHOT_ORIENTATION', defaultValue: '');

  static const String sampleDigestAsset = 'assets/sample_digest.json';
}
