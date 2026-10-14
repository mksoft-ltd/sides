import 'package:flutter_test/flutter_test.dart';
import 'package:sides/features/digest/domain/refresh_policy.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 10, 15, 9, 0);

  bool decide(String date, DateTime fetchedAt, {DateTime? at}) =>
      RefreshPolicy.shouldRevalidate(
        digestDate: date,
        fetchedAt: fetchedAt,
        now: at ?? now,
      );

  test("today's digest fetched an hour ago is fresh", () {
    expect(decide('2026-10-15', now.subtract(const Duration(hours: 1))),
        isFalse);
  });

  test("yesterday's digest is stale even if fetched a minute ago", () {
    expect(decide('2026-10-14', now.subtract(const Duration(minutes: 1))),
        isTrue);
  });

  test('more than 6 h since fetching revalidates', () {
    expect(decide('2026-10-15', now.subtract(const Duration(hours: 6, minutes: 1))),
        isTrue);
    expect(decide('2026-10-15', now.subtract(const Duration(hours: 6))),
        isFalse);
  });

  test('a fetched-at in the future (clock changed) revalidates', () {
    expect(decide('2026-10-15', now.add(const Duration(hours: 2))), isTrue);
  });

  test('"today" is the UTC day, not the local one', () {
    // 00:30 UTC on the 15th is still the 14th in New York (UTC-4).
    final DateTime justAfterMidnightUtc = DateTime.utc(2026, 10, 15, 0, 30);
    expect(
      decide('2026-10-14', justAfterMidnightUtc.subtract(const Duration(minutes: 5)),
          at: justAfterMidnightUtc),
      isTrue,
    );
    expect(RefreshPolicy.utcDay(DateTime.utc(2026, 1, 5, 23, 59)), '2026-01-05');
  });
}
