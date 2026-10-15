import 'package:flutter_test/flutter_test.dart';
import 'package:sides/features/digest/domain/digest.dart';

import '../fixtures/fixtures.dart';

/// On-read integrity (`Story.fromJson`): one test per rule, each introducing
/// exactly one violation into story 1 of the real sample digest.
///
/// Ids below were read by hand from `assets/sample_digest.json`:
/// story 1 (`c8bbc1a001c2`) has article `7809db6abcec` (Fox News);
/// `4246a58e693e` is an article of story 2, not of story 1.
void main() {
  const String s1Article = '7809db6abcec';
  const String s2Article = '4246a58e693e';
  const String unknown = 'ffffffffffff';

  Map<String, Object?> story1(Map<String, Object?> digest) =>
      (digest['stories']! as List<Object?>).first! as Map<String, Object?>;

  List<Object?> listIn(Map<String, Object?> m, String key) =>
      m[key]! as List<Object?>;

  /// Parses the sample after [mutate] has edited story 1.
  Story parsed(void Function(Map<String, Object?> s) mutate) {
    final Map<String, Object?> j = sampleDigestJson();
    mutate(story1(j));
    return Digest.fromJson(
      j,
    ).stories.firstWhere((Story s) => s.id == 'c8bbc1a001c2');
  }

  Map<String, Object?> point(String text, List<String> sources) =>
      <String, Object?>{'text': text, 'sources': sources};

  test('baseline: the unmutated story keeps its points', () {
    final Story s = parsed((_) {});
    expect(s.agreedFacts, isNotEmpty);
    expect(s.omissions, hasLength(3));
    expect(s.framingByLean, hasLength(3));
    expect(s.article(s1Article), isNotNull);
    expect(s.article(s2Article), isNull);
  });

  test('rule: an empty sources list drops the point', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'agreed_facts').add(point('Bare claim', <String>[]));
    });
    expect(
      s.agreedFacts.map((SourcedPoint p) => p.text),
      isNot(contains('Bare claim')),
    );
  });

  test('rule: an id from another story does not count as a source', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(
        st,
        'agreed_facts',
      ).add(point('Borrowed claim', <String>[s2Article]));
    });
    expect(
      s.agreedFacts.map((SourcedPoint p) => p.text),
      isNot(contains('Borrowed claim')),
    );
  });

  test('rule: duplicate source ids collapse to one chip', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(
        st,
        'opinion',
      ).add(point('Twice cited', <String>[s1Article, s1Article, unknown]));
    });
    expect(
      s.opinion
          .singleWhere((SourcedPoint p) => p.text == 'Twice cited')
          .sources,
      <String>[s1Article],
    );
  });

  test('rule: a non-string id is ignored rather than crashing', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'opinion').add(<String, Object?>{
        'text': 'Odd ids',
        'sources': <Object?>[42, null, s1Article],
      });
    });
    expect(
      s.opinion.singleWhere((SourcedPoint p) => p.text == 'Odd ids').sources,
      <String>[s1Article],
    );
  });

  test('rule: an unsourced emphasis point inside a framing is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      final Map<String, Object?> left =
          listIn(st, 'framing').first! as Map<String, Object?>;
      listIn(left, 'emphasis').add(point('Left spin', <String>[unknown]));
    });
    expect(
      s.framingFor(Lean.left)!.emphasis.map((SourcedPoint p) => p.text),
      isNot(contains('Left spin')),
    );
  });

  test(
    'rule: an unsourced emphasis point inside a bloc framing is dropped',
    () {
      final Story s = parsed((Map<String, Object?> st) {
        final Map<String, Object?> east = listIn(st, 'framing_by_bloc')
            .cast<Map<String, Object?>>()
            .firstWhere((Map<String, Object?> f) => f['bloc'] == 'east');
        listIn(east, 'emphasis').add(point('East spin', <String>[unknown]));
      });
      expect(
        s.framingForBloc(Bloc.east)!.emphasis.map((SourcedPoint p) => p.text),
        isNot(contains('East spin')),
      );
    },
  );

  test('rule: a quote whose article does not resolve is dropped', () {
    late int before;
    final Story s = parsed((Map<String, Object?> st) {
      final Map<String, Object?> left =
          listIn(st, 'framing').first! as Map<String, Object?>;
      final List<Object?> quotes = listIn(left, 'headline_quotes');
      before = quotes.length;
      quotes.add(<String, Object?>{
        'article_id': unknown,
        'quote': 'Invented headline',
        'field': 'headline',
      });
    });
    final List<HeadlineQuote> quotes = s.framingFor(Lean.left)!.headlineQuotes;
    expect(quotes, hasLength(before));
    expect(
      quotes.map((HeadlineQuote q) => q.quote),
      isNot(contains('Invented headline')),
    );
  });

  test('rule: a quote citing another story\'s article is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      final Map<String, Object?> left =
          listIn(st, 'framing').first! as Map<String, Object?>;
      listIn(left, 'headline_quotes').add(<String, Object?>{
        'article_id': s2Article,
        'quote': 'Borrowed headline',
        'field': 'headline',
      });
    });
    expect(
      s.framingFor(Lean.left)!.headlineQuotes.map((HeadlineQuote q) => q.quote),
      isNot(contains('Borrowed headline')),
    );
  });

  test('rule: an unsourced omission is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'omissions').add(<String, Object?>{
        'lean': 'right',
        'text': 'Nobody said this',
        'sources': <String>[unknown],
      });
    });
    expect(s.omissions, hasLength(3));
    expect(
      s.omissions.map((Omission o) => o.point.text),
      isNot(contains('Nobody said this')),
    );
  });

  test('rule: a contested claim with no resolvable asserter is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'contested_claims').add(<String, Object?>{
        'claim': 'Disputed but unasserted',
        'asserted_by': <String>[unknown],
        'disputed_by': <String>[s1Article],
      });
    });
    expect(s.contestedClaims, isEmpty);
  });

  test('rule: a contested claim with no resolvable disputer is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'contested_claims').add(<String, Object?>{
        'claim': 'Asserted but undisputed',
        'asserted_by': <String>[s1Article],
        'disputed_by': <String>[s2Article],
      });
    });
    expect(s.contestedClaims, isEmpty);
  });

  test('rule: a contested claim keeps only its resolvable ids', () {
    final List<String> ids = sampleDigest().stories.first.articles
        .map((Article a) => a.id)
        .toList();
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'contested_claims').add(<String, Object?>{
        'claim': 'Two-sided',
        'asserted_by': <String>[ids[0], unknown],
        'disputed_by': <String>[ids[1]],
      });
    });
    final ContestedClaim c = s.contestedClaims.single;
    expect(c.assertedBy, <String>[ids[0]]);
    expect(c.disputedBy, <String>[ids[1]]);
  });

  test('rule: a contradiction whose West side is unsourced is dropped', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'east_west_contradictions').add(<String, Object?>{
        'topic': 'Casualty figures',
        'west': point('w', <String>[]),
        'east': point('e', <String>[s1Article]),
      });
    });
    expect(s.contradictions, isEmpty);
  });

  test('rule: a fully sourced contradiction is kept (positive control)', () {
    final Story s = parsed((Map<String, Object?> st) {
      listIn(st, 'east_west_contradictions').add(<String, Object?>{
        'topic': 'Casualty figures',
        'west': point('w', <String>[s1Article]),
        'east': point('e', <String>[s1Article, unknown]),
      });
    });
    expect(s.contradictions.single.east.sources, <String>[s1Article]);
  });

  test('rule: a framing for an unknown lean rejects the digest', () {
    final Map<String, Object?> j = sampleDigestJson();
    (listIn(story1(j), 'framing').first! as Map<String, Object?>)['lean'] =
        'far-left';
    expect(() => Digest.fromJson(j), throwsA(isA<DigestFormatException>()));
  });

  test('rule: an omission without a lean rejects the digest', () {
    final Map<String, Object?> j = sampleDigestJson();
    (listIn(story1(j), 'omissions').first! as Map<String, Object?>)['lean'] =
        null;
    expect(() => Digest.fromJson(j), throwsA(isA<DigestFormatException>()));
  });
}
