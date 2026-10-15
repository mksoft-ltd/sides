import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/data/digest_remote.dart';
import 'package:sides/features/digest/data/digest_repository.dart';
import 'package:sides/features/digest/presentation/providers/digest_controller.dart';

import '../fixtures/fixtures.dart';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) server;
  late DateTime now;

  ProviderContainer container(InMemoryDigestCache cache) {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(
          NetworkDigestRepository(
            cache: cache,
            remote: DigestRemote(
              client: MockClient((http.Request r) async {
                requests.add(r);
                return server(r);
              }),
            ),
            clock: () => now,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  InMemoryDigestCache cachedAt(DateTime fetchedAt) => InMemoryDigestCache(
        CachedDigest(body: sampleDigestBody(), fetchedAt: fetchedAt, etag: '"v1"'),
      );

  Future<DigestState> settle(ProviderContainer c) async {
    c.read(digestControllerProvider);
    await pumpEventQueue();
    return c.read(digestControllerProvider);
  }

  setUp(() {
    requests = <http.Request>[];
    server = (_) => http.Response('', 304);
    now = DateTime.utc(2026, 10, 14, 23);
  });

  test('fresh cache on launch: shown, no network call', () async {
    final DigestState s =
        await settle(container(cachedAt(now.subtract(const Duration(hours: 1)))));
    expect(s.digest!.stories, hasLength(10));
    expect(requests, isEmpty);
  });

  test("next day's launch: cache shown and revalidated once", () async {
    now = DateTime.utc(2026, 10, 15, 7);
    final DigestState s =
        await settle(container(cachedAt(DateTime.utc(2026, 10, 14, 23))));
    expect(requests, hasLength(1));
    expect(s.digest, isNotNull);
    expect(s.lastFailure, isNull);
  });

  test('offline launch with a stale cache keeps the cache and flags offline',
      () async {
    now = DateTime.utc(2026, 10, 15, 7);
    server = (_) => throw http.ClientException('offline');
    final DigestState s =
        await settle(container(cachedAt(DateTime.utc(2026, 10, 14, 23))));
    expect(s.digest, isNotNull);
    expect(s.lastFailure, RefreshFailureKind.offline);
    expect(s.refreshing, isFalse);
  });

  test('pull-to-refresh fetches even when fresh; concurrent calls share one',
      () async {
    final ProviderContainer c =
        container(cachedAt(now.subtract(const Duration(minutes: 5))));
    await settle(c);
    final DigestController ctl = c.read(digestControllerProvider.notifier);
    await Future.wait(<Future<void>>[ctl.refresh(), ctl.refresh()]);
    expect(requests, hasLength(1));
  });

  test('resume revalidates only when the policy says so', () async {
    final ProviderContainer c =
        container(cachedAt(now.subtract(const Duration(minutes: 5))));
    await settle(c);
    await c.read(digestControllerProvider.notifier).onResumed();
    expect(requests, isEmpty);
    now = now.add(const Duration(hours: 7));
    await c.read(digestControllerProvider.notifier).onResumed();
    expect(requests, hasLength(1));
  });

  test('resume just after UTC midnight revalidates a 10-minute-old cache',
      () async {
    now = DateTime.utc(2026, 10, 14, 23, 55);
    final ProviderContainer c =
        container(cachedAt(DateTime.utc(2026, 10, 14, 23, 50)));
    await settle(c);
    expect(requests, isEmpty, reason: 'same UTC day, 5 minutes old');

    now = DateTime.utc(2026, 10, 15, 0, 0, 1);
    await c.read(digestControllerProvider.notifier).onResumed();
    expect(requests, hasLength(1));
    expect(requests.single.headers['If-None-Match'], '"v1"');
  });

  test('resume while the launch read is still pending does not fetch',
      () async {
    final ProviderContainer c =
        container(cachedAt(DateTime.utc(2025, 1, 1)));
    c.read(digestControllerProvider);
    // No pump: the cache has not been read yet.
    await c.read(digestControllerProvider.notifier).onResumed();
    expect(requests, isEmpty);
    await pumpEventQueue();
    expect(requests, hasLength(1), reason: 'launch itself revalidates once');
  });

  test('a failed refresh then a successful one clears the failure', () async {
    now = DateTime.utc(2026, 10, 15, 7);
    server = (_) => throw http.ClientException('offline');
    final ProviderContainer c =
        container(cachedAt(DateTime.utc(2026, 10, 14, 23)));
    expect((await settle(c)).lastFailure, RefreshFailureKind.offline);

    server = (_) => http.Response('', 304);
    await c.read(digestControllerProvider.notifier).refresh();
    final DigestState s = c.read(digestControllerProvider);
    expect(s.lastFailure, isNull);
    expect(s.loaded!.fetchedAt, now);
  });
}
