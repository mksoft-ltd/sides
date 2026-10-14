import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sides/features/digest/data/digest_cache.dart';
import 'package:sides/features/digest/data/digest_remote.dart';
import 'package:sides/features/digest/data/digest_repository.dart';

import '../fixtures/fixtures.dart';

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
      );

  http.Response ok(String etag) => http.Response.bytes(
        File(sampleDigestPath).readAsBytesSync(),
        200,
        headers: <String, String>{
          'etag': etag,
          'content-type': 'application/json',
        },
      );

  setUp(() {
    requests = <http.Request>[];
    now = DateTime.utc(2026, 10, 14, 23);
  });

  test('first launch: no cache, 200 is parsed and cached with its ETag', () async {
    server = (_) => ok('"v1"');
    final InMemoryDigestCache cache = InMemoryDigestCache();
    final NetworkDigestRepository r = repo(cache);

    expect(await r.loadCached(), isNull);
    final RefreshOutcome out = await r.refresh();

    expect(out, isA<RefreshUpdated>());
    expect((out as RefreshUpdated).loaded.digest.stories, hasLength(10));
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    expect(cache.value!.etag, '"v1"');
    expect(cache.value!.fetchedAt, now);
  });

  test('UTF-8 is decoded even when no charset is served', () async {
    server = (_) => ok('"v1"');
    final RefreshUpdated out =
        await repo(InMemoryDigestCache()).refresh() as RefreshUpdated;
    // The sample contains curly quotes in headlines.
    final bool hasCurly = out.loaded.digest.stories
        .expand((s) => s.articles)
        .any((a) => a.headline.contains('’') || a.snippet.contains('’'));
    expect(hasCurly, isTrue);
  });

  test('304: sends If-None-Match, keeps the body, bumps fetched-at', () async {
    final InMemoryDigestCache cache = InMemoryDigestCache(
      CachedDigest(
        body: sampleDigestBody(),
        fetchedAt: now.subtract(const Duration(hours: 7)),
        etag: '"v1"',
      ),
    );
    server = (_) => http.Response('', 304, headers: <String, String>{'etag': '"v1"'});
    final NetworkDigestRepository r = repo(cache);
    final LoadedDigest cached = (await r.loadCached())!;
    expect(r.needsRevalidation(cached), isTrue);

    final RefreshOutcome out = await r.refresh(current: cached);

    expect(out, isA<RefreshUnchanged>());
    expect(requests.single.headers['If-None-Match'], '"v1"');
    expect(cache.writes, 0);
    expect(cache.value!.fetchedAt, now);
    expect(r.needsRevalidation((out as RefreshUnchanged).loaded), isFalse);
  });

  test('offline with a cache: failure is reported, cache untouched', () async {
    server = (_) => throw http.ClientException('Failed host lookup');
    final InMemoryDigestCache cache = TestHarnessCache.fresh(now);
    final NetworkDigestRepository r = repo(cache);
    final LoadedDigest cached = (await r.loadCached())!;

    final RefreshOutcome out = await r.refresh(current: cached);

    expect((out as RefreshFailed).kind, RefreshFailureKind.offline);
    expect(cache.writes, 0);
    expect(await r.loadCached(), isNotNull);
  });

  test('offline with no cache: offline failure, nothing to show', () async {
    server = (_) => throw const SocketException('no network');
    final NetworkDigestRepository r = repo(InMemoryDigestCache());
    expect(await r.loadCached(), isNull);
    expect(((await r.refresh()) as RefreshFailed).kind, RefreshFailureKind.offline);
  });

  test('a malformed body never overwrites a good cache', () async {
    server = (_) => http.Response('{"schema_version":1}', 200);
    final InMemoryDigestCache cache = TestHarnessCache.fresh(now);
    final NetworkDigestRepository r = repo(cache);
    final RefreshOutcome out = await r.refresh(current: await r.loadCached());
    expect((out as RefreshFailed).kind, RefreshFailureKind.invalid);
    expect(cache.writes, 0);
  });

  test('a newer schema version is refused as unsupported', () async {
    server = (_) => http.Response.bytes(
        utf8.encode(sampleDigestBody()
            .replaceFirst('"schema_version": 1', '"schema_version": 2')),
        200);
    final RefreshOutcome out = await repo(InMemoryDigestCache()).refresh();
    expect((out as RefreshFailed).kind, RefreshFailureKind.unsupportedVersion);
  });

  test('HTTP 404 is a server failure', () async {
    server = (_) => http.Response('nope', 404);
    final RefreshOutcome out = await repo(InMemoryDigestCache()).refresh();
    expect((out as RefreshFailed).kind, RefreshFailureKind.server);
  });

  test('FileDigestCache round-trips body, ETag and fetched-at', () async {
    final Directory dir = await Directory.systemTemp.createTemp('sides_cache');
    addTearDown(() => dir.delete(recursive: true));
    final FileDigestCache cache = FileDigestCache(dir);
    expect(await cache.read(), isNull);
    await cache.write(CachedDigest(body: '{"a":1}', fetchedAt: now, etag: '"x"'));
    await cache.touch(fetchedAt: now.add(const Duration(hours: 1)));
    final CachedDigest back = (await cache.read())!;
    expect(back.body, '{"a":1}');
    expect(back.etag, '"x"');
    expect(back.fetchedAt, now.add(const Duration(hours: 1)));
    expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
  });
}

abstract final class TestHarnessCache {
  static InMemoryDigestCache fresh(DateTime now) => InMemoryDigestCache(
        CachedDigest(
          body: sampleDigestBody(),
          fetchedAt: now.subtract(const Duration(minutes: 10)),
          etag: '"v1"',
        ),
      );
}
