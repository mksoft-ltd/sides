import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';

sealed class FetchResult {
  const FetchResult();
}

/// 200 with a fresh body.
final class FetchedDigest extends FetchResult {
  const FetchedDigest({required this.body, this.etag});
  final String body;
  final String? etag;
}

/// 304: the cached copy is still current.
final class NotModified extends FetchResult {
  const NotModified({this.etag});
  final String? etag;
}

enum FetchFailureKind {
  /// No connection, DNS failure, timeout.
  offline,

  /// Reached the server but it did not return a digest (4xx/5xx).
  server,
}

final class FetchFailed extends FetchResult {
  const FetchFailed(this.kind, [this.detail]);
  final FetchFailureKind kind;
  final String? detail;
}

/// GETs the public digest with a conditional request.
class DigestRemote {
  DigestRemote({
    required this._client,
    Uri? url,
    this.timeout = AppConfig.fetchTimeout,
  }) : url = url ?? Uri.parse(AppConfig.digestUrl);

  final http.Client _client;
  final Uri url;
  final Duration timeout;

  Future<FetchResult> fetch({String? etag}) async {
    try {
      final http.Response r = await _client.get(
        url,
        headers: <String, String>{
          'Accept': 'application/json',
          'If-None-Match': ?etag,
        },
      ).timeout(timeout);
      final String? newEtag = r.headers['etag'];
      if (r.statusCode == 304) return NotModified(etag: newEtag ?? etag);
      if (r.statusCode == 200) {
        // Decode as UTF-8 regardless of the served charset: GitHub Pages
        // sends application/json without one and http would fall back to
        // Latin-1, mangling every curly quote in the headlines.
        return FetchedDigest(body: utf8.decode(r.bodyBytes), etag: newEtag);
      }
      return FetchFailed(FetchFailureKind.server, 'HTTP ${r.statusCode}');
    } on TimeoutException {
      return const FetchFailed(FetchFailureKind.offline, 'timeout');
    } on SocketException catch (e) {
      return FetchFailed(FetchFailureKind.offline, e.message);
    } on http.ClientException catch (e) {
      return FetchFailed(FetchFailureKind.offline, e.message);
    } on HandshakeException catch (e) {
      return FetchFailed(FetchFailureKind.offline, e.message);
    } on FormatException catch (e) {
      // Body not valid UTF-8.
      return FetchFailed(FetchFailureKind.server, e.message);
    } catch (e) {
      debugPrint('Digest fetch failed: $e');
      return FetchFailed(FetchFailureKind.offline, '$e');
    }
  }
}
