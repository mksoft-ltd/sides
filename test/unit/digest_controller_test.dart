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
}
