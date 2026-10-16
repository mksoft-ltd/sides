import 'package:flutter/foundation.dart';

import '../../digest/domain/digest.dart';

/// One story that matched a search, with the digest it lives in.
@immutable
class SearchHit {
  const SearchHit({
    required this.digest,
    required this.story,
    required this.score,
  });
  final Digest digest;
  final Story story;

  /// Higher first: how many query terms matched, weighted by where.
  final int score;
}

const Set<String> _stop = <String>{
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'at', 'by',
  'with', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been', 'its', 'it',
  'this', 'that', 'after', 'over', 'amid', 'into', 'new', 'says', 'say',
  'said', 'than', 'more', 'about', 'up', 'out', 'off', 'will', 'can', 'how',
  'why', 'what', 'who', 'when', 'where', 'his', 'her', 'their', 'has',
  'have', 'had', 'not', 'but', 'news',
};

/// Lower-cased content words of a query (≥ 2 chars, stop words out, in
/// order, at most 8). Mirrors the topic worker's `queryTerms`.
List<String> queryTerms(String query) {
  final Iterable<String> words = RegExp(r'[a-z0-9]+')
      .allMatches(_fold(query))
      .map((Match m) => m.group(0)!);
  final List<String> out = <String>[];
  for (final String w in words) {
    if (w.length < 2 || _stop.contains(w) || out.contains(w)) continue;
    out.add(w);
    if (out.length >= 8) break;
  }
  return out;
}

String _fold(String s) => s
    .replaceAll('‘', "'")
    .replaceAll('’', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .toLowerCase();

bool _termIn(String term, String hay) {
  final String t = RegExp.escape(term);
  // Words of four letters or more match as a word start ("strike" ~
  // "strikes"); shorter ones must match whole.
  final RegExp re = term.length >= 4 ? RegExp('\\b$t') : RegExp('\\b$t\\b');
  return re.hasMatch(hay);
}

/// Every story across [digests] that matches [query], best first. A story
/// matches when every term appears in its title, summary, headlines or
/// snippets; if nothing matches that way, stories matching at least two
/// terms (or one, for a one-term query) are returned instead. Each story
/// appears once, newest digest first for equal scores.
List<SearchHit> searchStories(Iterable<Digest> digests, String query) {
  final List<String> terms = queryTerms(query);
  if (terms.isEmpty) return const <SearchHit>[];
  final List<_Scored> scored = <_Scored>[];
  final Set<String> seen = <String>{};
  for (final Digest d in digests) {
    for (final Story s in d.stories) {
      if (!seen.add('${d.date}/${s.id}')) continue;
      final String title = _fold('${s.title} ${s.summary?.text ?? ''}');
      final String body = _fold(
        s.articles.map((Article a) => '${a.headline} ${a.snippet}').join(' '),
      );
      int hits = 0;
      int score = 0;
      for (final String t in terms) {
        final bool inTitle = _termIn(t, title);
        final bool inBody = _termIn(t, body);
        if (inTitle || inBody) hits++;
        score += (inTitle ? 3 : 0) + (inBody ? 1 : 0);
      }
      if (hits > 0) scored.add(_Scored(d, s, hits, score));
    }
  }
  final int need = terms.length;
  List<_Scored> kept = scored.where((_Scored x) => x.hits == need).toList();
  if (kept.isEmpty) {
    final int min = need == 1 ? 1 : 2;
    kept = scored.where((_Scored x) => x.hits >= min).toList();
  }
  kept.sort((_Scored a, _Scored b) {
    final int c = b.score.compareTo(a.score);
    if (c != 0) return c;
    final int d = b.digest.date.compareTo(a.digest.date);
    return d != 0 ? d : a.story.rank.compareTo(b.story.rank);
  });
  return <SearchHit>[
    for (final _Scored x in kept)
      SearchHit(digest: x.digest, story: x.story, score: x.score),
  ];
}

class _Scored {
  const _Scored(this.digest, this.story, this.hits, this.score);
  final Digest digest;
  final Story story;
  final int hits;
  final int score;
}
