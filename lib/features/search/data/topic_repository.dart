// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../digest/data/digest_repository.dart';
import '../../digest/domain/digest.dart';

/// What the topic service said.
sealed class TopicOutcome {
  const TopicOutcome();
}

/// A digest with one story: the comparison for the topic.
final class TopicReady extends TopicOutcome {
  const TopicReady(this.digest, {required this.cached});
  final Digest digest;
  final bool cached;
}

/// Peek only: the shared cache has nothing for these words today.
final class TopicMiss extends TopicOutcome {
  const TopicMiss();
}

/// Fewer than three outlets wrote about those words today.
final class TopicNoMatch extends TopicOutcome {
  const TopicNoMatch();
}

/// Today's analysis budget is spent; cached topics still work.
final class TopicCapped extends TopicOutcome {
  const TopicCapped();
}

/// This device asked for too many new topics this hour.
final class TopicRateLimited extends TopicOutcome {
  const TopicRateLimited();
}

final class TopicFailed extends TopicOutcome {
  const TopicFailed(this.message);
  final String message;
}

/// Today's topic comparisons, cheapest source first:
/// [onPhone] (instant, offline) → [peek] (the shared server cache, free) →
/// [analyse] (a new comparison, paid, polled while `pending`).
abstract class TopicRepository {
  /// A comparison this phone already received today for these words.
  TopicReady? onPhone(String query);

  /// The shared cache only: ready, no_match, or null for "nothing yet".
  /// Never starts an analysis and never counts against any limit.
  Future<TopicOutcome?> peek(String query);

  Future<TopicOutcome> analyse(String query);
}

/// The cache key: the query's content words, sorted, plus today's date
/// (UTC), so "Starlink Ukraine" and "ukraine starlink" share an entry, as
/// they do on the server.
String topicKey(String query, DateTime nowUtc) {
  final List<String> terms = RegExp(r'[a-z0-9]+')
      .allMatches(query.toLowerCase())
      .map((Match m) => m.group(0)!)
      .where((String w) => w.length >= 2)
      .toSet()
      .toList()
    ..sort();
  final String day = nowUtc.toIso8601String().substring(0, 10);
  return '$day|${terms.join(' ')}';
}

class NetworkTopicRepository implements TopicRepository {
  NetworkTopicRepository({
    required http.Client client,
    Uri? url,
    DigestParser parse = NetworkDigestRepository.defaultParser,
    this.timeout = AppConfig.topicTimeout,
    this.pollInterval = const Duration(seconds: 5),
    this.maxPolls = 24,
    DateTime Function()? clock,
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _client = client,
        _url = url ?? Uri.parse(AppConfig.topicUrl),
        _parse = parse;

  final http.Client _client;
  final Uri _url;
  final DigestParser _parse;
  final Duration timeout;
  final Duration pollInterval;
  final int maxPolls;
  final DateTime Function() _clock;
  final Map<String, TopicReady> _onPhone = <String, TopicReady>{};

  @override
  TopicReady? onPhone(String query) => _onPhone[topicKey(query, _clock())];

  TopicOutcome _remember(String query, TopicOutcome o) {
    if (o is TopicReady) _onPhone[topicKey(query, _clock())] = o;
    return o;
  }

  @override
  Future<TopicOutcome?> peek(String query) async {
    final TopicOutcome? o = await _once(query, peek: true);
    if (o == null || o is TopicMiss) return null;
    return _remember(query, o);
  }

  @override
  Future<TopicOutcome> analyse(String query) async {
    for (int attempt = 0; attempt <= maxPolls; attempt++) {
      final TopicOutcome? outcome = await _once(query);
      if (outcome != null) return _remember(query, outcome);
      await Future<void>.delayed(pollInterval);
    }
    return const TopicFailed('The comparison is taking too long. Try again.');
  }

  /// One request; null means "pending, ask again".
  Future<TopicOutcome?> _once(String query, {bool peek = false}) async {
    final Uri url = _url.replace(queryParameters: <String, String>{
      'q': query,
      if (peek) 'peek': '1',
    });
    http.Response r;
    try {
      r = await _client
          .get(url, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      return const TopicFailed('The comparison timed out. Try again.');
    } on Object catch (e) {
      debugPrint('Topic request failed: $e');
      return const TopicFailed('Could not reach the topic service.');
    }
    if (r.statusCode != 200) return TopicFailed('HTTP ${r.statusCode}');
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return const TopicFailed('The topic service sent an unreadable answer.');
    }
    if (decoded is! Map<String, Object?>) {
      return const TopicFailed('The topic service sent an unreadable answer.');
    }
    switch (decoded['status']) {
      case 'ready':
        final Object? digestJson = decoded['digest'];
        if (digestJson is! Map<String, Object?>) {
          return const TopicFailed('The comparison was missing from the answer.');
        }
        final Digest? digest = (await _parse(jsonEncode(digestJson))).digest;
        if (digest == null || digest.stories.isEmpty) {
          return const TopicFailed('The comparison could not be read.');
        }
        return TopicReady(digest, cached: decoded['cached'] == true);
      case 'pending':
        return null;
      case 'miss':
        return const TopicMiss();
      case 'no_match':
        return const TopicNoMatch();
      case 'capped':
        return const TopicCapped();
      case 'rate_limited':
        return const TopicRateLimited();
      default:
        return TopicFailed(decoded['message'] as String? ?? 'Unknown answer.');
    }
  }
}
