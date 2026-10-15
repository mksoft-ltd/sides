import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/data/digest_remote.dart';
import 'package:sides/features/digest/data/digest_repository.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/digest/presentation/providers/digest_controller.dart';

import '../fixtures/fixtures.dart';

/// ETag / status / body edge cases and cache-corruption recovery.
///
/// The invariant every test here guards: the cache only ever changes to a
/// body that parsed as a supported digest, and a broken cache is recovered
/// from rather than shown or crashed on.
void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) server;
  late DateTime now;

  NetworkDigestRepository repo(DigestCache cache) => NetworkDigestRepository(
    cache: cache,
    remote: DigestRemote(
      client: MockClient((http.Request r) async {
        requests.add(r);
        return server(r);
      }),
    ),
    clock: () => now,
    // Controller tests here settle with pumpEventQueue, which does not wait
    // for an isolate; digest_repository_test.dart runs the background parse.
    parse: parseDigestInline,
  );

  /// The sample with a different `date`, so a replaced body is detectable.
  String bodyDated(String date) => sampleDigestBody().replaceFirst(
    '"date": "2026-10-14"',
    '"date": "$date"',
  );

  http.Response ok(String body, {String? etag}) => http.Response.bytes(
    utf8.encode(body),
    200,
    headers: <String, String>{'etag': ?etag},
  );

  InMemoryDigestCache goodCache() => InMemoryDigestCache(
    CachedDigest(
      body: sampleDigestBody(),
      fetchedAt: DateTime.utc(2026, 10, 14, 16),
      etag: '"v1"',
    ),
  );

  setUp(() {
    requests = <http.Request>[];
    now = DateTime.utc(2026, 10, 14, 23);
  });

  /// Real file IO is not a microtask: wait (bounded) for the controller to
  /// finish its launch instead of trusting pumpEventQueue.
  Future<DigestState> launched(ProviderContainer c) async {
    c.read(digestControllerProvider);
    for (int i = 0; i < 500; i++) {
      final DigestState s = c.read(digestControllerProvider);
      if (!s.initialising && !s.refreshing && requests.isNotEmpty) return s;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('controller never finished launching');
  }

  group('ETag: 304 vs 200', () {
    test('304 without an ETag header keeps the ETag we already had', () async {
      server = (_) => http.Response('', 304);
      final InMemoryDigestCache cache = goodCache();
      final NetworkDigestRepository r = repo(cache);

      final RefreshOutcome out = await r.refresh(current: await r.loadCached());

      expect(requests.single.headers['If-None-Match'], '"v1"');
      expect((out as RefreshUnchanged).loaded.etag, '"v1"');
      expect(cache.value!.etag, '"v1"');
      expect(cache.value!.body, sampleDigestBody());
      expect(cache.value!.fetchedAt, now);
    });

    test(
      '304 with a rotated ETag stores the new one, body untouched',
      () async {
        server = (_) =>
            http.Response('', 304, headers: <String, String>{'etag': '"v2"'});
        final InMemoryDigestCache cache = goodCache();
        final NetworkDigestRepository r = repo(cache);

        await r.refresh(current: await r.loadCached());

        expect(cache.value!.etag, '"v2"');
        expect(cache.writes, 0);
        expect(cache.value!.body, sampleDigestBody());
      },
    );

    test(
      '304 when we sent no ETag is a server failure, nothing cached',
      () async {
        server = (_) => http.Response('', 304);
        final InMemoryDigestCache cache = InMemoryDigestCache();

        final RefreshOutcome out = await repo(cache).refresh();

        expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
        expect((out as RefreshFailed).kind, RefreshFailureKind.server);
        expect(cache.value, isNull);
      },
    );

    test(
      '200 over an existing cache replaces body, ETag and fetched-at',
      () async {
        server = (_) => ok(bodyDated('2026-10-15'), etag: '"v2"');
        final InMemoryDigestCache cache = goodCache();
        final NetworkDigestRepository r = repo(cache);

        final RefreshOutcome out = await r.refresh(
          current: await r.loadCached(),
        );

        expect((out as RefreshUpdated).loaded.digest.date, '2026-10-15');
        expect(cache.writes, 1);
        expect(cache.value!.etag, '"v2"');
        expect(cache.value!.fetchedAt, now);
        expect((await r.loadCached())!.digest.date, '2026-10-15');
      },
    );

    test('200 without an ETag header caches the body with no ETag, so the '
        'next request is unconditional', () async {
      server = (_) => ok(bodyDated('2026-10-15'));
      final InMemoryDigestCache cache = goodCache();
      final NetworkDigestRepository r = repo(cache);

      await r.refresh(current: await r.loadCached());
      await r.refresh(current: await r.loadCached());

      expect(cache.value!.etag, isNull);
      expect(requests.last.headers.containsKey('If-None-Match'), isFalse);
    });
  });

  group('a bad 200 body never clobbers the cache', () {
    final Map<String, String> badBodies = <String, String>{
      'captive-portal HTML':
          '<!doctype html><html><body>Sign in to Wi-Fi'
          '</body></html>',
      'truncated JSON': sampleDigestBody().substring(0, 4000),
      'empty body': '',
      'top-level array': '[1, 2, 3]',
      'JSON null': 'null',
      'wrong field type (stories is a string)':
          '{"schema_version": 1, "generated_at": "2026-10-15T06:00:00Z", '
          '"date": "2026-10-15", "meta": {}, "outlets": [], '
          '"stories": "none"}',
    };

    for (final MapEntry<String, String> bad in badBodies.entries) {
      test('${bad.key}: invalid, cache and ETag untouched', () async {
        server = (_) => ok(bad.value, etag: '"bad"');
        final InMemoryDigestCache cache = goodCache();
        final NetworkDigestRepository r = repo(cache);

        final RefreshOutcome out = await r.refresh(
          current: await r.loadCached(),
        );

        expect((out as RefreshFailed).kind, RefreshFailureKind.invalid);
        expect(cache.writes, 0);
        expect(cache.value!.etag, '"v1"');
        expect(cache.value!.body, sampleDigestBody());
        expect((await r.loadCached())!.digest.stories, hasLength(10));
      });
    }

    test('a newer schema version: unsupported, cache untouched', () async {
      server = (_) => ok(
        sampleDigestBody().replaceFirst(
          '"schema_version": 1',
          '"schema_version": 2',
        ),
        etag: '"v2"',
      );
      final InMemoryDigestCache cache = goodCache();
      final NetworkDigestRepository r = repo(cache);

      final RefreshOutcome out = await r.refresh(current: await r.loadCached());

      expect(
        (out as RefreshFailed).kind,
        RefreshFailureKind.unsupportedVersion,
      );
      expect(cache.writes, 0);
      expect(cache.value!.etag, '"v1"');
    });

    test('bytes that are not UTF-8: server failure, cache untouched', () async {
      server = (_) => http.Response.bytes(<int>[0xff, 0xfe, 0x7b], 200);
      final InMemoryDigestCache cache = goodCache();
      final NetworkDigestRepository r = repo(cache);

      final RefreshOutcome out = await r.refresh(current: await r.loadCached());

      expect((out as RefreshFailed).kind, RefreshFailureKind.server);
      expect(cache.writes, 0);
    });

    test('HTTP 500 with a JSON-looking body is a server failure', () async {
      server = (_) => http.Response.bytes(utf8.encode(sampleDigestBody()), 500);
      final InMemoryDigestCache cache = goodCache();
      final NetworkDigestRepository r = repo(cache);

      final RefreshOutcome out = await r.refresh(current: await r.loadCached());

      expect((out as RefreshFailed).kind, RefreshFailureKind.server);
      expect(cache.writes, 0);
    });
  });

  group('cache corruption recovery (FileDigestCache)', () {
    late Directory dir;
    late FileDigestCache cache;

    File body() => File('${dir.path}/latest.json');
    File meta() => File('${dir.path}/latest.meta.json');

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sides_corrupt');
      cache = FileDigestCache(dir);
      await cache.write(
        CachedDigest(
          body: sampleDigestBody(),
          fetchedAt: DateTime.utc(2026, 10, 14, 16),
          etag: '"v1"',
        ),
      );
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test(
      'a torn body file reads as no cache, then a 200 replaces it',
      () async {
        body().writeAsStringSync(sampleDigestBody().substring(0, 777));
        server = (_) => ok(bodyDated('2026-10-15'), etag: '"v2"');
        final NetworkDigestRepository r = repo(cache);
        expect(await r.loadCached(), isNull);

        // Launch through the controller, as the app does.
        final ProviderContainer c = ProviderContainer(
          overrides: <Override>[digestRepositoryProvider.overrideWithValue(r)],
        );
        addTearDown(c.dispose);
        final DigestState s = await launched(c);

        expect(s.digest!.date, '2026-10-15');
        expect(
          requests.single.headers.containsKey('If-None-Match'),
          isFalse,
          reason:
              'a broken cache must not send its ETag: a 304 would '
              'leave the reader with nothing',
        );
        final LoadedDigest back = (await r.loadCached())!;
        expect(back.digest.date, '2026-10-15');
        expect(back.etag, '"v2"');
      },
    );

    test('garbage metadata reads as no cache', () async {
      meta().writeAsStringSync('{not json');
      expect(await cache.read(), isNull);
      expect(await repo(cache).loadCached(), isNull);
    });

    test('metadata without fetched_at reads as no cache', () async {
      meta().writeAsStringSync('{"etag": "\\"v1\\""}');
      expect(await cache.read(), isNull);
    });

    test('metadata that is a JSON list reads as no cache', () async {
      meta().writeAsStringSync('[]');
      expect(await cache.read(), isNull);
    });

    test('a body with no metadata file reads as no cache', () async {
      meta().deleteSync();
      expect(await cache.read(), isNull);
    });

    test('a leftover temp file from a crash mid-write is ignored', () async {
      File('${dir.path}/latest.json.123-0.tmp').writeAsStringSync('{"half": ');
      final LoadedDigest? back = await repo(cache).loadCached();
      expect(back, isNotNull);
      expect(back!.digest.stories, hasLength(10));
      expect(back.etag, '"v1"');
    });

    test('a cached body from a newer schema reads as no cache', () async {
      body().writeAsStringSync(
        sampleDigestBody().replaceFirst(
          '"schema_version": 1',
          '"schema_version": 2',
        ),
      );
      expect(await repo(cache).loadCached(), isNull);
    });

    test('touch on a corrupt cache is a no-op, not a crash', () async {
      meta().writeAsStringSync('garbage');
      await cache.touch(fetchedAt: now, etag: '"v9"');
      expect(meta().readAsStringSync(), 'garbage');
    });

    test('a torn cache + offline launch: offline state, no crash', () async {
      body().writeAsStringSync('{');
      server = (_) => throw const SocketException('no network');
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          digestRepositoryProvider.overrideWithValue(repo(cache)),
        ],
      );
      addTearDown(c.dispose);
      final DigestState s = await launched(c);
      expect(s.digest, isNull);
      expect(s.refreshing, isFalse);
      expect(s.lastFailure, RefreshFailureKind.offline);
    });
  });

  group('fix round 2', () {
    test('m4: an unexpected cache-read exception is a miss, not an endless '
        'first-screen spinner', () async {
      server = (_) => ok(bodyDated('2026-10-15'), etag: '"v2"');
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          digestRepositoryProvider.overrideWithValue(
            _CacheReadExplodes(repo(InMemoryDigestCache())),
          ),
        ],
      );
      addTearDown(c.dispose);
      final DigestState s = await launched(c);
      expect(s.initialising, isFalse, reason: 'the spinner must clear');
      expect(requests, hasLength(1), reason: 'treated as a miss: fetch');
      expect(s.digest?.date, '2026-10-15');
    });

    test('m5: the default parser runs off the UI isolate and returns the '
        'same digest as the pure parse', () async {
      final String body = sampleDigestBody();
      final ParsedDigest bg = await parseDigestInBackground(body);
      final ParsedDigest inline = parseDigest(body);
      expect(bg.failure, isNull);
      expect(
        bg.digest!.stories.map((Story s) => s.id).toList(),
        inline.digest!.stories.map((Story s) => s.id).toList(),
      );
      expect((await parseDigestInBackground('{not json')).failure,
          RefreshFailureKind.invalid);
      // Production builds the repository without a parser (lib/main.dart),
      // so the default is what keeps the parse off the UI isolate.
      expect(NetworkDigestRepository.defaultParser,
          same(parseDigestInBackground));
    });
  });

  group('cache write failures (disk full, permissions)', () {
    // Regression for F1 (docs/TEST_PLAN.md): a FileSystemException from
    // DigestCache.write/touch used to escape DigestController._refresh and
    // leave `refreshing == true` forever.
    test('first launch on a full disk: the downloaded digest is shown and '
        'the spinner clears', () async {
      server = (_) => ok(bodyDated('2026-10-15'), etag: '"v2"');
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          digestRepositoryProvider.overrideWithValue(repo(ThrowingCache())),
        ],
      );
      addTearDown(c.dispose);
      c.read(digestControllerProvider);
      await pumpEventQueue();

      final DigestState s = c.read(digestControllerProvider);
      expect(
        s.refreshing,
        isFalse,
        reason:
            'with no cache, refreshing=true is the endless '
            '"Loading today\'s digest" spinner with no Retry',
      );
      expect(
        s.digest,
        isNotNull,
        reason: 'the body parsed; failing to save it should not hide it',
      );
    });

    test('pull-to-refresh on a full disk completes without throwing', () async {
      server = (_) => ok(bodyDated('2026-10-15'), etag: '"v2"');
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          digestRepositoryProvider.overrideWithValue(
            repo(
              ThrowingCache(
                CachedDigest(
                  body: sampleDigestBody(),
                  fetchedAt: now.subtract(const Duration(minutes: 5)),
                  etag: '"v1"',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(digestControllerProvider);
      await pumpEventQueue();

      await expectLater(
        c.read(digestControllerProvider.notifier).refresh(),
        completes,
        reason: 'RefreshIndicator awaits this future',
      );
      expect(c.read(digestControllerProvider).refreshing, isFalse);
    });

    test('any exception from the repository ends the refresh, keeps the '
        'cached digest and surfaces a failure', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          digestRepositoryProvider.overrideWithValue(
            _ExplodingRepository(repo(goodCache())),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(digestControllerProvider);
      await pumpEventQueue();

      final DigestState s = c.read(digestControllerProvider);
      expect(s.refreshing, isFalse);
      expect(s.digest, isNotNull, reason: 'the cache stays on screen');
      expect(s.lastFailure, RefreshFailureKind.server);
      await expectLater(
        c.read(digestControllerProvider.notifier).refresh(),
        completes,
      );
    });
  });
}

/// Reads the real cache but fails every refresh with an unexpected error.
/// `loadCached` throws something no parser catches (code review m4).
class _CacheReadExplodes extends _ExplodingRepository {
  _CacheReadExplodes(super.inner);

  @override
  Future<LoadedDigest?> loadCached() async =>
      throw StateError('asset bundle unavailable');

  @override
  Future<RefreshOutcome> refresh({LoadedDigest? current}) =>
      _inner.refresh(current: current);
}

class _ExplodingRepository implements DigestRepository {
  _ExplodingRepository(this._inner);
  final DigestRepository _inner;

  @override
  Future<LoadedDigest?> loadCached() => _inner.loadCached();

  @override
  bool needsRevalidation(LoadedDigest current) => true;

  @override
  Future<RefreshOutcome> refresh({LoadedDigest? current}) async =>
      throw const FileSystemException('No space left on device');
}

/// A cache whose writes fail as `FileDigestCache` does on a full disk.
class ThrowingCache extends InMemoryDigestCache {
  ThrowingCache([super.value]);

  @override
  Future<void> write(CachedDigest v) async =>
      throw const FileSystemException('No space left on device');

  @override
  Future<void> touch({required DateTime fetchedAt, String? etag}) async =>
      throw const FileSystemException('No space left on device');
}
