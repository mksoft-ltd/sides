import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import '../../../core/config/app_config.dart';
import '../../../core/time/clock.dart';
import '../domain/digest.dart';
import '../domain/refresh_policy.dart';
import 'digest_cache.dart';
import 'digest_remote.dart';

/// A parsed digest and when this phone last confirmed it was current.
@immutable
class LoadedDigest {
  const LoadedDigest({
    required this.digest,
    required this.fetchedAt,
    this.etag,
  });
  final Digest digest;
  final DateTime fetchedAt;
  final String? etag;
}

enum RefreshFailureKind {
  offline,
  server,

  /// The server answered with something that is not a valid digest.
  invalid,

  /// A newer schema than this build understands; the user should update.
  unsupportedVersion,
}

sealed class RefreshOutcome {
  const RefreshOutcome();
}

final class RefreshUpdated extends RefreshOutcome {
  const RefreshUpdated(this.loaded);
  final LoadedDigest loaded;
}

final class RefreshUnchanged extends RefreshOutcome {
  const RefreshUnchanged(this.loaded);
  final LoadedDigest loaded;
}

final class RefreshFailed extends RefreshOutcome {
  const RefreshFailed(this.kind);
  final RefreshFailureKind kind;
}

/// What the digest controller needs. Two implementations: the network one
/// used by real users, and a bundled one for screenshots/debug preview.
abstract class DigestRepository {
  /// The cached digest, or null if there is none or it no longer parses.
  Future<LoadedDigest?> loadCached();

  /// Whether [current] should be revalidated on launch/resume.
  bool needsRevalidation(LoadedDigest current);

  /// Fetches the latest digest, conditional on [current]'s ETag.
  Future<RefreshOutcome> refresh({LoadedDigest? current});
}

/// Turns a digest body into a [Digest] (or the reason it was refused).
typedef DigestParser = Future<ParsedDigest> Function(String body);

typedef ParsedDigest = ({Digest? digest, RefreshFailureKind? failure});

/// The default parser: [parseDigest] on a background isolate. A digest is
/// ~150 KB, so decoding and modelling it on the UI isolate costs a visible
/// frame on low-end Android (code review m5). The parse is a pure top-level
/// function over a String and its result is plain immutable data, so it
/// crosses the isolate boundary as-is.
Future<ParsedDigest> parseDigestInBackground(String body) =>
    compute(parseDigest, body, debugLabel: 'parseDigest');

/// Same parse on the calling isolate. Widget tests use it: they run in a
/// fake-async zone where a real isolate's reply would never be awaited.
Future<ParsedDigest> parseDigestInline(String body) async => parseDigest(body);

class NetworkDigestRepository implements DigestRepository {
  NetworkDigestRepository({
    required this._cache,
    required this._remote,
    this._clock = systemClock,
    this._parse = defaultParser,
  });

  /// What production uses (main.dart passes no parser): off the UI isolate.
  static const DigestParser defaultParser = parseDigestInBackground;

  final DigestCache _cache;
  final DigestRemote _remote;
  final Clock _clock;
  final DigestParser _parse;

  @override
  Future<LoadedDigest?> loadCached() async {
    final CachedDigest? cached = await _cache.read();
    if (cached == null) return null;
    final Digest? digest = (await _parse(cached.body)).digest;
    if (digest == null) return null;
    return LoadedDigest(
      digest: digest,
      fetchedAt: cached.fetchedAt,
      etag: cached.etag,
    );
  }

  @override
  bool needsRevalidation(LoadedDigest current) =>
      RefreshPolicy.shouldRevalidate(
        digestDate: current.digest.date,
        fetchedAt: current.fetchedAt,
        now: _clock(),
      );

  @override
  Future<RefreshOutcome> refresh({LoadedDigest? current}) async {
    final FetchResult result = await _remote.fetch(etag: current?.etag);
    final DateTime now = _clock().toUtc();
    switch (result) {
      case FetchFailed(:final FetchFailureKind kind):
        return RefreshFailed(
          kind == FetchFailureKind.offline
              ? RefreshFailureKind.offline
              : RefreshFailureKind.server,
        );
      case NotModified(:final String? etag):
        if (current == null) {
          // We sent no ETag, so a 304 is a misbehaving cache in between.
          return const RefreshFailed(RefreshFailureKind.server);
        }
        // A failed save (full disk) must not hide a digest we already have.
        await _saveQuietly(() => _cache.touch(fetchedAt: now, etag: etag));
        return RefreshUnchanged(
          LoadedDigest(
            digest: current.digest,
            fetchedAt: now,
            etag: etag ?? current.etag,
          ),
        );
      case FetchedDigest(:final String body, :final String? etag):
        final ParsedDigest parsed = await _parse(body);
        final Digest? digest = parsed.digest;
        if (digest == null) {
          // Never overwrite a good cache with a bad file.
          return RefreshFailed(parsed.failure!);
        }
        // The body parsed, so show it even if it cannot be saved (F1).
        await _saveQuietly(
          () => _cache.write(
            CachedDigest(body: body, fetchedAt: now, etag: etag),
          ),
        );
        return RefreshUpdated(
          LoadedDigest(digest: digest, fetchedAt: now, etag: etag),
        );
    }
  }
}

/// Runs a cache write. A storage failure (full disk, revoked permissions)
/// costs only persistence: the next launch fetches again.
Future<void> _saveQuietly(Future<void> Function() save) async {
  try {
    await save();
  } on Exception catch (e) {
    debugPrint('Digest cache not saved: $e');
  }
}

/// Serves the bundled sample digest. Debug/profile/screenshot only: the
/// provider that chooses a repository refuses this one in release builds.
class BundledDigestRepository implements DigestRepository {
  BundledDigestRepository({required this._bundle});

  final AssetBundle _bundle;

  Future<LoadedDigest?> _load() async {
    final String body = await _bundle.loadString(AppConfig.sampleDigestAsset);
    final Digest? digest = parseDigest(body).digest;
    if (digest == null) return null;
    return LoadedDigest(digest: digest, fetchedAt: digest.generatedAt);
  }

  @override
  Future<LoadedDigest?> loadCached() => _load();

  @override
  bool needsRevalidation(LoadedDigest current) => false;

  @override
  Future<RefreshOutcome> refresh({LoadedDigest? current}) async {
    final LoadedDigest? loaded = await _load();
    if (loaded == null) {
      return const RefreshFailed(RefreshFailureKind.invalid);
    }
    return RefreshUnchanged(loaded);
  }
}

/// Pure: body in, digest or refusal out. No I/O, no globals, so it runs
/// unchanged on a background isolate ([parseDigestInBackground]).
ParsedDigest parseDigest(String body) {
  try {
    final Object? json = jsonDecode(body);
    if (json is! Map<String, Object?>) {
      return (digest: null, failure: RefreshFailureKind.invalid);
    }
    if (json['schema_version'] != AppConfig.supportedSchemaVersion) {
      return (digest: null, failure: RefreshFailureKind.unsupportedVersion);
    }
    return (digest: Digest.fromJson(json), failure: null);
  } on FormatException {
    return (digest: null, failure: RefreshFailureKind.invalid);
  } on DigestFormatException catch (e) {
    debugPrint('Digest rejected: $e');
    return (digest: null, failure: RefreshFailureKind.invalid);
  }
}
