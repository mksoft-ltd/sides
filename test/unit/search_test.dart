import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sides/features/digest/data/digest_repository.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/search/data/topic_repository.dart';
import 'package:sides/features/search/domain/search.dart';

import '../fixtures/fixtures.dart';

void main() {
  final Digest digest = sampleDigest();

  group('searchStories', () {
    test('query terms drop stop words, fold case and cap at eight', () {
      expect(queryTerms('The Pope and his cancer'), <String>['pope', 'cancer']);
      expect(queryTerms('  '), isEmpty);
      expect(queryTerms('aa bb cc dd ee ff gg hh ii jj'), hasLength(8));
    });

    test('every-term matches come first; title hits outrank body hits', () {
      final List<SearchHit> hits = searchStories(<Digest>[digest], 'Pope cancer');
      expect(hits, isNotEmpty);
      expect(hits.first.story.rank, 1, reason: 'the Pope story leads the sample');
      for (final SearchHit h in hits) {
        expect(h.digest.date, digest.date);
      }
    });

    test('a word that appears in no story returns nothing', () {
      expect(searchStories(<Digest>[digest], 'zebra'), isEmpty);
    });

    test('a story appears once even when two digests carry it', () {
      final List<SearchHit> hits =
          searchStories(<Digest>[digest, digest], 'Starlink');
      final Set<String> ids = hits.map((SearchHit h) => h.story.id).toSet();
      expect(ids.length, hits.length);
    });

    test('word starts match for four letters and more: strike ⊇ strikes', () {
      final Set<String> a =
          searchStories(<Digest>[digest], 'strike').map((SearchHit h) => h.story.id).toSet();
      final Set<String> b =
          searchStories(<Digest>[digest], 'strikes').map((SearchHit h) => h.story.id).toSet();
      expect(b, isNotEmpty);
      expect(a.containsAll(b), isTrue);
    });
  });

  group('NetworkTopicRepository', () {
    NetworkTopicRepository repo(http.Response Function(http.Request) handler) =>
        NetworkTopicRepository(
          client: MockClient((http.Request r) async => handler(r)),
          url: Uri.parse('https://topic.example/v1/topic'),
          parse: parseDigestInline,
          pollInterval: Duration.zero,
          maxPolls: 2,
          clock: () => DateTime.utc(2026, 10, 17, 9),
        );

    test('ready: the digest is parsed and the cached flag kept', () async {
      final Map<String, Object?> body = <String, Object?>{
        'status': 'ready',
        'cached': true,
        'digest': sampleDigestJson(),
      };
      http.Request? seen;
      final TopicOutcome o = await repo((http.Request r) {
        seen = r;
        // Bytes, not a String: the sample carries curly quotes (UTF-8).
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }).analyse('pope cancer');
      expect(o, isA<TopicReady>());
      expect((o as TopicReady).cached, isTrue);
      expect(o.digest.stories, isNotEmpty);
      expect(seen!.url.queryParameters['q'], 'pope cancer');
    });

    test('pending is polled until it resolves', () async {
      int n = 0;
      final TopicOutcome o = await repo((http.Request r) {
        n++;
        return http.Response(
          jsonEncode(n < 3
              ? <String, Object?>{'status': 'pending', 'retry_after': 5}
              : <String, Object?>{'status': 'no_match', 'matched_outlets': 1}),
          200,
        );
      }).analyse('x');
      expect(o, isA<TopicNoMatch>());
      expect(n, 3);
    });

    test('still pending after the poll limit is a failure, not a hang',
        () async {
      final TopicOutcome o = await repo(
        (_) => http.Response('{"status":"pending"}', 200),
      ).analyse('x');
      expect(o, isA<TopicFailed>());
    });

    test('capped, rate_limited, errors and junk map to their outcomes',
        () async {
      expect(await repo((_) => http.Response('{"status":"capped"}', 200)).analyse('x'),
          isA<TopicCapped>());
      expect(
          await repo((_) => http.Response('{"status":"rate_limited"}', 200))
              .analyse('x'),
          isA<TopicRateLimited>());
      expect(await repo((_) => http.Response('boom', 500)).analyse('x'),
          isA<TopicFailed>());
      expect(await repo((_) => http.Response('not json', 200)).analyse('x'),
          isA<TopicFailed>());
      expect(
          await repo((_) => http.Response('{"status":"ready","digest":5}', 200))
              .analyse('x'),
          isA<TopicFailed>());
      expect(
          await repo((_) => throw http.ClientException('offline')).analyse('x'),
          isA<TopicFailed>());
    });
  });

  group('peek and the phone cache', () {
    test('peek sends peek=1; a miss is null and remembers nothing', () async {
      http.Request? seen;
      final NetworkTopicRepository r = NetworkTopicRepository(
        client: MockClient((http.Request req) async {
          seen = req;
          return http.Response('{"status":"miss"}', 200);
        }),
        url: Uri.parse('https://topic.example/v1/topic'),
        parse: parseDigestInline,
        clock: () => DateTime.utc(2026, 10, 17, 9),
      );
      expect(await r.peek('Starlink Ukraine'), isNull);
      expect(seen!.url.queryParameters['peek'], '1');
      expect(r.onPhone('Starlink Ukraine'), isNull);
    });

    test('a ready answer is kept on the phone for the same words today, in '
        'any order, and not tomorrow', () async {
      DateTime now = DateTime.utc(2026, 10, 17, 9);
      final NetworkTopicRepository r = NetworkTopicRepository(
        client: MockClient((http.Request req) async => http.Response.bytes(
              utf8.encode(jsonEncode(<String, Object?>{
                'status': 'ready',
                'cached': true,
                'digest': sampleDigestJson(),
              })),
              200,
            )),
        url: Uri.parse('https://topic.example/v1/topic'),
        parse: parseDigestInline,
        clock: () => now,
      );
      expect(await r.peek('Starlink Ukraine'), isA<TopicReady>());
      expect(r.onPhone('ukraine  STARLINK'), isNotNull);
      now = DateTime.utc(2026, 10, 18, 9);
      expect(r.onPhone('Starlink Ukraine'), isNull);
    });
  });
}
