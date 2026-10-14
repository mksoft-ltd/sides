import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sides/features/digest/domain/digest.dart';

import '../fixtures/fixtures.dart';

void main() {
  group('real sample digest (14 Oct 2026)', () {
    late Digest d;
    setUpAll(() => d = sampleDigest());

    test('top-level fields', () {
      expect(d.schemaVersion, 1);
      expect(d.date, '2026-10-14');
      expect(d.generatedAt.isUtc, isTrue);
      expect(d.outlets, hasLength(29));
      expect(d.stories, hasLength(10));
      expect(d.stories.map((Story s) => s.rank), <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(d.meta.model, isNotEmpty);
    });

    test('outlets carry lean, bloc and ownership; state media has no lean', () {
      final Outlet guardian = d.outlet('guardian')!;
      expect(guardian.lean, Lean.left);
      expect(guardian.bloc, Bloc.west);
      expect(guardian.ownership, Ownership.independent);
      final List<Outlet> state =
          d.outlets.where((Outlet o) => o.isStateControlled).toList();
      expect(state, isNotEmpty);
      expect(state.every((Outlet o) => o.lean == null), isTrue);
    });

    test('story 1 has all three leans and both blocs', () {
      final Story s = d.stories.first;
      expect(s.outletCount, 12);
      expect(s.coverage.left, 6);
      expect(s.coverage.centre, 3);
      expect(s.coverage.right, 2);
      expect(s.coverage.west, 11);
      expect(s.coverage.east, 1);
      expect(s.leansPresent, <Lean>[Lean.left, Lean.centre, Lean.right]);
      expect(s.blocsPresent, <Bloc>[Bloc.west, Bloc.east]);
      expect(s.agreedFacts, isNotEmpty);
    });

    test('story 7 is a left-only lean blindspot', () {
      final Story s = d.stories[6];
      expect(s.rank, 7);
      expect(s.blindspot.lean, Lean.left);
      expect(s.blindspot.bloc, isNull);
      expect(s.leansPresent, <Lean>[Lean.left]);
    });

    test('quote field is read: both headline and snippet quotes exist', () {
      final List<HeadlineQuote> quotes = <HeadlineQuote>[
        for (final Story s in d.stories)
          for (final Framing<Lean> f in s.framingByLean) ...f.headlineQuotes,
          for (final Story s in d.stories)
          for (final Framing<Bloc> f in s.framingByBloc) ...f.headlineQuotes,
      ];
      expect(quotes.where((HeadlineQuote q) => q.field == QuoteField.headline),
          isNotEmpty);
      expect(quotes.where((HeadlineQuote q) => q.field == QuoteField.snippet),
          isNotEmpty);
    });

    test('every analytical point resolves to an article in its story', () {
      for (final Story s in d.stories) {
        final List<SourcedPoint> all = <SourcedPoint>[
          ...s.agreedFacts,
          ...s.opinion,
          for (final Omission o in s.omissions) o.point,
          for (final Framing<Lean> f in s.framingByLean) ...f.emphasis,
          for (final Framing<Bloc> f in s.framingByBloc) ...f.emphasis,
        ];
        for (final SourcedPoint p in all) {
          expect(p.sources, isNotEmpty);
          expect(p.sources.every((String id) => s.article(id) != null), isTrue);
        }
      }
    });

    test('no contradictions today, so the placeholder path is exercised', () {
      expect(d.stories.every((Story s) => s.contradictions.isEmpty), isTrue);
    });
  });

  group('integrity rules on read', () {
    Map<String, Object?> mutate(void Function(Map<String, Object?> story) f) {
      final Map<String, Object?> j = sampleDigestJson();
      f((j['stories']! as List<Object?>).first! as Map<String, Object?>);
      return j;
    }

    test('a point whose sources are all unknown is dropped', () {
      final Map<String, Object?> j = mutate((Map<String, Object?> s) {
        (s['agreed_facts']! as List<Object?>).insert(0, <String, Object?>{
          'text': 'Unsourced claim',
          'sources': <String>['ffffffffffff'],
        });
      });
      final Story s = Digest.fromJson(j).stories.first;
      expect(s.agreedFacts.map((SourcedPoint p) => p.text),
          isNot(contains('Unsourced claim')));
    });

    test('unknown ids are stripped but the known ones keep the point', () {
      late String known;
      final Map<String, Object?> j = mutate((Map<String, Object?> s) {
        known = ((s['articles']! as List<Object?>).first!
            as Map<String, Object?>)['id']! as String;
        (s['opinion']! as List<Object?>).add(<String, Object?>{
          'text': 'Half sourced',
          'sources': <String>['ffffffffffff', known],
        });
      });
      final SourcedPoint p = Digest.fromJson(j)
          .stories
          .first
          .opinion
          .firstWhere((SourcedPoint p) => p.text == 'Half sourced');
      expect(p.sources, <String>[known]);
    });

    test('a contradiction with one unsourced side is dropped', () {
      late String known;
      final Map<String, Object?> j = mutate((Map<String, Object?> s) {
        known = ((s['articles']! as List<Object?>).first!
            as Map<String, Object?>)['id']! as String;
        (s['east_west_contradictions']! as List<Object?>).add(<String, Object?>{
          'topic': 'Casualty figures',
          'west': <String, Object?>{'text': 'w', 'sources': <String>[known]},
          'east': <String, Object?>{
            'text': 'e',
            'sources': <String>['ffffffffffff'],
          },
        });
      });
      expect(Digest.fromJson(j).stories.first.contradictions, isEmpty);
    });

    test('a quote without the field property defaults to headline', () {
      final Map<String, Object?> j = mutate((Map<String, Object?> s) {
        final Map<String, Object?> framing =
            (s['framing']! as List<Object?>).first! as Map<String, Object?>;
        for (final Object? q in framing['headline_quotes']! as List<Object?>) {
          (q! as Map<String, Object?>).remove('field');
        }
      });
      final Story s = Digest.fromJson(j).stories.first;
      expect(
        s.framingByLean.first.headlineQuotes
            .every((HeadlineQuote q) => q.field == QuoteField.headline),
        isTrue,
      );
    });

    test('a structurally broken digest throws DigestFormatException', () {
      final Map<String, Object?> j = sampleDigestJson()..remove('stories');
      expect(() => Digest.fromJson(j), throwsA(isA<DigestFormatException>()));
      expect(
        () => Digest.fromJson(
          jsonDecode('{"schema_version":1,"generated_at":"x"}')
              as Map<String, Object?>,
        ),
        throwsA(isA<DigestFormatException>()),
      );
    });
  });
}
