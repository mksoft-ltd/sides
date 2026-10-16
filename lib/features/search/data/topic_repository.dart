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

/// Asks the topic service for a comparison. A `pending` answer (another
/// reader asked for the same topic seconds ago) is polled until it resolves.
abstract class TopicRepository {
  Future<TopicOutcome> analyse(String query);
}

class NetworkTopicRepository implements TopicRepository {
  NetworkTopicRepository({
    required http.Client client,
    Uri? url,
    DigestParser parse = NetworkDigestRepository.defaultParser,
    this.timeout = AppConfig.topicTimeout,
    this.pollInterval = const Duration(seconds: 5),
    this.maxPolls = 24,
  })  : _client = client,
        _url = url ?? Uri.parse(AppConfig.topicUrl),
        _parse = parse;

  final http.Client _client;
  final Uri _url;
  final DigestParser _parse;
  final Duration timeout;
  final Duration pollInterval;
  final int maxPolls;

  @override
  Future<TopicOutcome> analyse(String query) async {
    for (int attempt = 0; attempt <= maxPolls; attempt++) {
      final TopicOutcome? outcome = await _once(query);
      if (outcome != null) return outcome;
      await Future<void>.delayed(pollInterval);
    }
    return const TopicFailed('The comparison is taking too long. Try again.');
  }

  /// One request; null means "pending, ask again".
  Future<TopicOutcome?> _once(String query) async {
    final Uri url = _url.replace(queryParameters: <String, String>{'q': query});
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
