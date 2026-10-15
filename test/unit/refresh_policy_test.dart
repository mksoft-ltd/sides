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
    expect(
      decide('2026-10-15', now.subtract(const Duration(hours: 1))),
      isFalse,
    );
  });

  test("yesterday's digest is stale even if fetched a minute ago", () {
    expect(
      decide('2026-10-14', now.subtract(const Duration(minutes: 1))),
      isTrue,
    );
  });

  test('more than 6 h since fetching revalidates', () {
    expect(
      decide('2026-10-15', now.subtract(const Duration(hours: 6, minutes: 1))),
      isTrue,
    );
    expect(
      decide('2026-10-15', now.subtract(const Duration(hours: 6))),
      isFalse,
    );
  });

  test('a fetched-at in the future (clock changed) revalidates', () {
    expect(decide('2026-10-15', now.add(const Duration(hours: 2))), isTrue);
  });

  test('"today" is the UTC day, not the local one', () {
    // 00:30 UTC on the 15th is still the 14th in New York (UTC-4).
    final DateTime justAfterMidnightUtc = DateTime.utc(2026, 10, 15, 0, 30);
    expect(
      decide(
        '2026-10-14',
        justAfterMidnightUtc.subtract(const Duration(minutes: 5)),
        at: justAfterMidnightUtc,
      ),
      isTrue,
    );
    expect(
      RefreshPolicy.utcDay(DateTime.utc(2026, 1, 5, 23, 59)),
      '2026-01-05',
    );
  });

  group('UTC midnight boundary', () {
    // A digest dated the 14th, fetched at 23:50 UTC on the 14th.
    final DateTime fetched = DateTime.utc(2026, 10, 14, 23, 50);

    test('the last instant of the day is still fresh', () {
      expect(
        decide(
          '2026-10-14',
          fetched,
          at: DateTime.utc(2026, 10, 14, 23, 59, 59, 999),
        ),
        isFalse,
      );
    });

    test('the first instant of the next UTC day is stale (10 min old)', () {
      expect(
        decide('2026-10-14', fetched, at: DateTime.utc(2026, 10, 15)),
        isTrue,
      );
    });

    test('a local-time "now" is judged by its UTC day', () {
      // 23:30 UTC on the 14th is already the 15th in Tokyo (UTC+9) and still
      // the 14th in London; whatever zone the test machine runs in, the
      // digest dated the 14th must count as today.
      final DateTime localNow = DateTime.utc(2026, 10, 14, 23, 30).toLocal();
      expect(
        decide('2026-10-14', DateTime.utc(2026, 10, 14, 23, 20), at: localNow),
        isFalse,
      );
    });

    test('a digest dated ahead of today (pipeline clock ahead) is not '
        'refetched on date alone', () {
      expect(
        decide('2026-10-16', now.subtract(const Duration(hours: 1))),
        isFalse,
      );
    });

    test('utcDay converts a local instant before formatting', () {
      // 23:30 UTC on 31 July is 00:30 on 1 August in London (BST) and
      // 08:30 in Tokyo, so this discriminates on any machine east of UTC.
      // On a UTC machine (CI) it cannot fail; see docs/TEST_PLAN.md.
      final DateTime instant = DateTime.utc(2026, 7, 31, 23, 30);
      expect(RefreshPolicy.utcDay(instant.toLocal()), '2026-07-31');
      expect(RefreshPolicy.utcDay(DateTime.utc(2027)), '2027-01-01');
    });
  });

  group('6 h rule', () {
    test('exactly 6 h is fresh; 6 h + 1 ms is stale', () {
      expect(
        decide('2026-10-15', now.subtract(const Duration(hours: 6))),
        isFalse,
      );
      expect(
        decide(
          '2026-10-15',
          now.subtract(const Duration(hours: 6, milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('the 6 h rule applies even to a digest dated today', () {
      // The pipeline may republish today after a failed morning run.
      final DateTime evening = DateTime.utc(2026, 10, 15, 20);
      expect(
        decide('2026-10-15', DateTime.utc(2026, 10, 15, 7), at: evening),
        isTrue,
      );
    });

    test(
      'a fetched-at given in local time is compared as UTC (behaviour pin)',
      () {
        // Not a guarded mechanism: DateTime.difference is instant-based.
        final DateTime fetchedLocal = now
            .subtract(const Duration(hours: 1))
            .toLocal();
        expect(decide('2026-10-15', fetchedLocal), isFalse);
      },
    );

    test('a fetched-at one millisecond in the future revalidates', () {
      expect(
        decide('2026-10-15', now.add(const Duration(milliseconds: 1))),
        isTrue,
      );
    });
  });
}
