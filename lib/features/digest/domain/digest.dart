import 'package:flutter/foundation.dart';

/// Immutable models mirroring `schema/digest.schema.json` (schema_version 1).
///
/// Parsing is strict about structure (a malformed digest is rejected rather
/// than half-shown) but the integrity rules are enforced on read: every
/// analytical point keeps only the source ids that resolve to an article in
/// its story, and a point left with none is dropped, so the UI can never
/// render an unsourced claim even if a bad file slipped past the pipeline's
/// citation validator.

class DigestFormatException implements Exception {
  const DigestFormatException(this.message);
  final String message;
  @override
  String toString() => 'DigestFormatException: $message';
}

enum Lean {
  left('left', 'Left'),
  centre('centre', 'Centre'),
  right('right', 'Right');

  const Lean(this.wire, this.label);
  final String wire;
  final String label;

  static Lean? fromWire(Object? value) {
    if (value == null) return null;
    for (final Lean l in values) {
      if (l.wire == value) return l;
    }
    throw DigestFormatException('unknown lean "$value"');
  }
}

enum Bloc {
  west('west', 'West', 'Western'),
  east('east', 'East', 'Eastern');

  const Bloc(this.wire, this.label, this.adjective);
  final String wire;
  final String label;
  final String adjective;

  static Bloc fromWire(Object? value) {
    for (final Bloc b in values) {
      if (b.wire == value) return b;
    }
    throw DigestFormatException('unknown bloc "$value"');
  }

  static Bloc? fromWireOrNull(Object? value) =>
      value == null ? null : fromWire(value);
}

enum Ownership {
  independent('independent', 'Independent'),
  publicService('public-service', 'Public service'),
  stateFunded('state-funded', 'State-funded'),
  stateControlled('state-controlled', 'State media');

  const Ownership(this.wire, this.label);
  final String wire;
  final String label;

  static Ownership fromWire(Object? value) {
    for (final Ownership o in values) {
      if (o.wire == value) return o;
    }
    throw DigestFormatException('unknown ownership "$value"');
  }
}

/// Which part of the source a headline quote was taken from.
enum QuoteField {
  headline('headline'),
  snippet('snippet');

  const QuoteField(this.wire);
  final String wire;

  /// Required by the schema (set by the pipeline's citation validator, not
  /// the model). A quote without it is a malformed digest.
  static QuoteField fromWire(Object? value) => switch (value) {
        'headline' => QuoteField.headline,
        'snippet' => QuoteField.snippet,
        _ => throw DigestFormatException('unknown quote field "$value"'),
      };
}

@immutable
class Outlet {
  const Outlet({
    required this.id,
    required this.name,
    required this.lean,
    required this.region,
    required this.bloc,
    required this.ownership,
    required this.country,
    required this.homeUrl,
    required this.ratingBasis,
  });

  final String id;
  final String name;
  final Lean? lean;

  /// Raw schema value (uk, us, europe, middle_east, asia, …).
  final String region;
  final Bloc bloc;
  final Ownership ownership;
  final String country;
  final String homeUrl;
  final String ratingBasis;

  bool get isStateControlled => ownership == Ownership.stateControlled;

  String get regionLabel => switch (region) {
        'uk' => 'UK',
        'us' => 'US',
        'europe' => 'Europe',
        'middle_east' => 'Middle East',
        'asia' => 'Asia',
        'africa' => 'Africa',
        'oceania' => 'Oceania',
        'americas' => 'Americas',
        _ => region,
      };

  factory Outlet.fromJson(Map<String, Object?> j) => Outlet(
        id: _str(j, 'id'),
        name: _str(j, 'name'),
        lean: Lean.fromWire(j['lean']),
        region: _str(j, 'region'),
        bloc: Bloc.fromWire(j['bloc']),
        ownership: Ownership.fromWire(j['ownership']),
        country: _str(j, 'country'),
        homeUrl: _str(j, 'home_url'),
        ratingBasis: _str(j, 'rating_basis'),
      );
}

@immutable
class Article {
  const Article({
    required this.id,
    required this.outletId,
    required this.headline,
    required this.snippet,
    required this.url,
    required this.publishedAt,
    this.publishedAtEstimated = false,
  });

  final String id;
  final String outletId;
  final String headline;

  /// At most 200 characters from the outlet's own feed summary.
  final String snippet;
  final String url;
  final DateTime publishedAt;
  final bool publishedAtEstimated;

  factory Article.fromJson(Map<String, Object?> j) => Article(
        id: _str(j, 'id'),
        outletId: _str(j, 'outlet_id'),
        headline: _str(j, 'headline'),
        snippet: _str(j, 'snippet'),
        url: _str(j, 'url'),
        publishedAt: _date(j, 'published_at'),
        publishedAtEstimated: j['published_at_estimated'] == true,
      );
}

/// One analytical point and the articles it rests on.
@immutable
class SourcedPoint {
  const SourcedPoint({required this.text, required this.sources});
  final String text;
  final List<String> sources;

  factory SourcedPoint.fromJson(Map<String, Object?> j) =>
      SourcedPoint(text: _str(j, 'text'), sources: _ids(j, 'sources'));
}

@immutable
class HeadlineQuote {
  const HeadlineQuote({
    required this.articleId,
    required this.quote,
    required this.field,
  });
  final String articleId;
  final String quote;
  final QuoteField field;

  factory HeadlineQuote.fromJson(Map<String, Object?> j) => HeadlineQuote(
        articleId: _str(j, 'article_id'),
        quote: _str(j, 'quote'),
        field: QuoteField.fromWire(j['field']),
      );
}

/// How one group (a lean or a bloc) frames the story.
@immutable
class Framing<G> {
  const Framing({
    required this.group,
    required this.headlineQuotes,
    required this.emphasis,
  });
  final G group;
  final List<HeadlineQuote> headlineQuotes;
  final List<SourcedPoint> emphasis;
}

@immutable
class Omission {
  const Omission({required this.lean, required this.point});

  /// The lean whose coverage does not mention the point.
  final Lean lean;

  /// The point, sourced to the articles (of other leans) that do carry it.
  final SourcedPoint point;
}

@immutable
class ContestedClaim {
  const ContestedClaim({
    required this.claim,
    required this.assertedBy,
    required this.disputedBy,
  });
  final String claim;
  final List<String> assertedBy;
  final List<String> disputedBy;
}

@immutable
class Contradiction {
  const Contradiction({
    required this.topic,
    required this.west,
    required this.east,
  });
  final String topic;
  final SourcedPoint west;
  final SourcedPoint east;
}

@immutable
class Coverage {
  const Coverage({
    required this.left,
    required this.centre,
    required this.right,
    required this.west,
    required this.east,
  });
  final int left;
  final int centre;
  final int right;
  final int west;
  final int east;

  int get leanTotal => left + centre + right;
  int get blocTotal => west + east;

  int forLean(Lean l) => switch (l) {
        Lean.left => left,
        Lean.centre => centre,
        Lean.right => right,
      };

  int forBloc(Bloc b) => b == Bloc.west ? west : east;

  factory Coverage.fromJson(Map<String, Object?> j) {
    final Map<String, Object?> lean = _map(j, 'lean');
    final Map<String, Object?> bloc = _map(j, 'bloc');
    return Coverage(
      left: _int(lean, 'left'),
      centre: _int(lean, 'centre'),
      right: _int(lean, 'right'),
      west: _int(bloc, 'west'),
      east: _int(bloc, 'east'),
    );
  }
}

@immutable
class Blindspot {
  const Blindspot({this.lean, this.bloc});

  /// The only lean that covered the story, when every other lean had none.
  final Lean? lean;

  /// The only bloc that covered the story, when the other had none.
  final Bloc? bloc;

  bool get any => lean != null || bloc != null;

  factory Blindspot.fromJson(Map<String, Object?> j) => Blindspot(
        lean: Lean.fromWire(j['lean']),
        bloc: Bloc.fromWireOrNull(j['bloc']),
      );
}

@immutable
/// What the pipeline's citation validator kept and dropped for one story.
@immutable
class StoryValidation {
  const StoryValidation({required this.kept, required this.droppedByReason});
  final int kept;
  final Map<String, int> droppedByReason;

  factory StoryValidation.fromJson(Map<String, Object?> j) => StoryValidation(
        kept: _int(j, 'kept'),
        droppedByReason: <String, int>{
          for (final MapEntry<String, Object?> e
              in _map(j, 'dropped_by_reason').entries)
            if (e.value case final int n) e.key: n,
        },
      );
}

class Story {
  Story._({
    required this.id,
    required this.title,
    required this.rank,
    required this.outletCount,
    required this.coverage,
    required this.blindspot,
    required this.articles,
    required this.agreedFacts,
    required this.framingByLean,
    required this.omissions,
    required this.contestedClaims,
    required this.opinion,
    required this.framingByBloc,
    required this.contradictions,
    this.validation,
  }) : _articleById = <String, Article>{
          for (final Article a in articles) a.id: a,
        };

  final String id;
  final String title;
  final int rank;
  final int outletCount;
  final Coverage coverage;
  final Blindspot blindspot;
  final List<Article> articles;
  final List<SourcedPoint> agreedFacts;
  final List<Framing<Lean>> framingByLean;
  final List<Omission> omissions;
  final List<ContestedClaim> contestedClaims;
  final List<SourcedPoint> opinion;
  final List<Framing<Bloc>> framingByBloc;
  final List<Contradiction> contradictions;

  /// The pipeline's validation counts (schema-required; null only for an
  /// older file without them, which then renders as before).
  final StoryValidation? validation;

  final Map<String, Article> _articleById;

  /// True when the analysis did not run or nothing of it survived: the
  /// validator kept nothing and every analysis list is empty. "None found"
  /// would then be a claim about an analysis that never happened, so the
  /// story page shows an "analysis unavailable" notice instead (code review
  /// M3).
  bool get analysisUnavailable =>
      validation?.kept == 0 &&
      agreedFacts.isEmpty &&
      framingByLean.isEmpty &&
      omissions.isEmpty &&
      contestedClaims.isEmpty &&
      opinion.isEmpty &&
      framingByBloc.isEmpty &&
      contradictions.isEmpty;

  Article? article(String id) => _articleById[id];

  /// Leans with a framing entry, in Left · Centre · Right order.
  List<Lean> get leansPresent => <Lean>[
        for (final Lean l in Lean.values)
          if (framingByLean.any((Framing<Lean> f) => f.group == l)) l,
      ];

  /// Blocs with a framing entry, in West · East order.
  List<Bloc> get blocsPresent => <Bloc>[
        for (final Bloc b in Bloc.values)
          if (framingByBloc.any((Framing<Bloc> f) => f.group == b)) b,
      ];

  Framing<Lean>? framingFor(Lean l) =>
      framingByLean.where((Framing<Lean> f) => f.group == l).firstOrNull;

  Framing<Bloc>? framingForBloc(Bloc b) =>
      framingByBloc.where((Framing<Bloc> f) => f.group == b).firstOrNull;

  factory Story.fromJson(Map<String, Object?> j) {
    final List<Article> articles =
        _list(j, 'articles').map(Article.fromJson).toList(growable: false);
    final Set<String> known = <String>{for (final Article a in articles) a.id};

    // Integrity rule: keep only resolvable sources, drop what is left bare.
    List<String> resolve(List<String> ids) =>
        ids.where(known.contains).toSet().toList(growable: false);

    SourcedPoint? sourced(Map<String, Object?> m) {
      final SourcedPoint p = SourcedPoint.fromJson(m);
      final List<String> ids = resolve(p.sources);
      return ids.isEmpty ? null : SourcedPoint(text: p.text, sources: ids);
    }

    List<SourcedPoint> points(List<Map<String, Object?>> raw) =>
        raw.map(sourced).nonNulls.toList(growable: false);

    List<HeadlineQuote> quotes(Map<String, Object?> m) => _list(
          m,
          'headline_quotes',
        )
            .map(HeadlineQuote.fromJson)
            .where((HeadlineQuote q) => known.contains(q.articleId))
            .toList(growable: false);

    return Story._(
      id: _str(j, 'id'),
      title: _str(j, 'title'),
      rank: _int(j, 'rank'),
      outletCount: _int(j, 'outlet_count'),
      coverage: Coverage.fromJson(_map(j, 'coverage')),
      blindspot: Blindspot.fromJson(_map(j, 'blindspot')),
      articles: articles,
      agreedFacts: points(_list(j, 'agreed_facts')),
      framingByLean: _list(j, 'framing')
          .map(
            (Map<String, Object?> m) => Framing<Lean>(
              group: Lean.fromWire(m['lean']) ??
                  (throw const DigestFormatException('framing without lean')),
              headlineQuotes: quotes(m),
              emphasis: points(_list(m, 'emphasis')),
            ),
          )
          .toList(growable: false),
      omissions: <Omission>[
        for (final Map<String, Object?> m in _list(j, 'omissions'))
          if (sourced(m) case final SourcedPoint p)
            Omission(
              lean: Lean.fromWire(m['lean']) ??
                  (throw const DigestFormatException('omission without lean')),
              point: p,
            ),
      ],
      contestedClaims: <ContestedClaim>[
        for (final Map<String, Object?> m in _list(j, 'contested_claims'))
          if ((
            resolve(_ids(m, 'asserted_by')),
            resolve(_ids(m, 'disputed_by')),
          )
              case (final List<String> a, final List<String> d)
              when a.isNotEmpty && d.isNotEmpty)
            ContestedClaim(
              claim: _str(m, 'claim'),
              assertedBy: a,
              disputedBy: d,
            ),
      ],
      opinion: points(_list(j, 'opinion')),
      framingByBloc: _list(j, 'framing_by_bloc')
          .map(
            (Map<String, Object?> m) => Framing<Bloc>(
              group: Bloc.fromWire(m['bloc']),
              headlineQuotes: quotes(m),
              emphasis: points(_list(m, 'emphasis')),
            ),
          )
          .toList(growable: false),
      contradictions: <Contradiction>[
        for (final Map<String, Object?> m
            in _list(j, 'east_west_contradictions'))
          if ((sourced(_map(m, 'west')), sourced(_map(m, 'east')))
              case (final SourcedPoint w, final SourcedPoint e))
            Contradiction(topic: _str(m, 'topic'), west: w, east: e),
      ],
      validation: j['validation'] == null
          ? null
          : StoryValidation.fromJson(_map(j, 'validation')),
    );
  }
}

@immutable
class DigestMeta {
  const DigestMeta({
    required this.model,
    required this.outletsPolled,
    required this.articlesCollected,
  });
  final String model;
  final int outletsPolled;
  final int articlesCollected;

  factory DigestMeta.fromJson(Map<String, Object?> j) => DigestMeta(
        model: _str(j, 'model'),
        outletsPolled: _int(j, 'outlets_polled'),
        articlesCollected: _int(j, 'articles_collected'),
      );
}

@immutable
class Digest {
  Digest._({
    required this.schemaVersion,
    required this.generatedAt,
    required this.date,
    required this.meta,
    required this.outlets,
    required this.stories,
  }) : _outletById = <String, Outlet>{for (final Outlet o in outlets) o.id: o};

  final int schemaVersion;
  final DateTime generatedAt;

  /// The digest's day as published (`YYYY-MM-DD`, UTC).
  final String date;
  final DigestMeta meta;
  final List<Outlet> outlets;
  final List<Story> stories;

  final Map<String, Outlet> _outletById;

  Outlet? outlet(String id) => _outletById[id];

  Story? story(String id) =>
      stories.where((Story s) => s.id == id).firstOrNull;

  factory Digest.fromJson(Map<String, Object?> j) {
    final List<Story> stories =
        _list(j, 'stories').map(Story.fromJson).toList()
          ..sort((Story a, Story b) => a.rank.compareTo(b.rank));
    return Digest._(
      schemaVersion: _int(j, 'schema_version'),
      generatedAt: _date(j, 'generated_at'),
      date: _str(j, 'date'),
      meta: DigestMeta.fromJson(_map(j, 'meta')),
      outlets: _list(j, 'outlets').map(Outlet.fromJson).toList(growable: false),
      stories: List<Story>.unmodifiable(stories),
    );
  }
}

// ---- strict JSON helpers -------------------------------------------------

String _str(Map<String, Object?> j, String k) => switch (j[k]) {
      final String v => v,
      _ => throw DigestFormatException('"$k" must be a string'),
    };

int _int(Map<String, Object?> j, String k) => switch (j[k]) {
      final int v => v,
      _ => throw DigestFormatException('"$k" must be an integer'),
    };

DateTime _date(Map<String, Object?> j, String k) {
  final DateTime? d = DateTime.tryParse(_str(j, k));
  if (d == null) throw DigestFormatException('"$k" is not a date-time');
  return d.toUtc();
}

Map<String, Object?> _map(Map<String, Object?> j, String k) => switch (j[k]) {
      final Map<String, Object?> v => v,
      _ => throw DigestFormatException('"$k" must be an object'),
    };

List<Map<String, Object?>> _list(Map<String, Object?> j, String k) =>
    switch (j[k]) {
      final List<Object?> v => <Map<String, Object?>>[
          for (final Object? e in v)
            if (e is Map<String, Object?>)
              e
            else
              throw DigestFormatException('"$k" must hold objects'),
        ],
      _ => throw DigestFormatException('"$k" must be an array'),
    };

List<String> _ids(Map<String, Object?> j, String k) => switch (j[k]) {
      final List<Object?> v => v.whereType<String>().toList(growable: false),
      _ => throw DigestFormatException('"$k" must be an array of ids'),
    };
