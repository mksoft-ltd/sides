import '../../../core/config/app_config.dart';

/// When a cached digest should be revalidated against the network.
///
/// Pure, so every case (today, stale date, 6 h age, clock skew) is a unit
/// test with a fixed clock. Pull-to-refresh bypasses this entirely.
abstract final class RefreshPolicy {
  /// True when the cached digest's date is before today (UTC) or it was
  /// fetched more than [AppConfig.maxCacheAge] ago. A fetched-at in the
  /// future (clock changed) also revalidates, rather than trusting it.
  static bool shouldRevalidate({
    required String digestDate,
    required DateTime fetchedAt,
    required DateTime now,
  }) {
    final DateTime nowUtc = now.toUtc();
    if (digestDate.compareTo(utcDay(nowUtc)) < 0) return true;
    final Duration age = nowUtc.difference(fetchedAt.toUtc());
    if (age.isNegative) return true;
    return age > AppConfig.maxCacheAge;
  }

  /// `YYYY-MM-DD` of [t] in UTC; ISO dates compare correctly as strings.
  static String utcDay(DateTime t) {
    final DateTime u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
  }
}
