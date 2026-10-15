import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/digest_repository.dart';
import '../../domain/digest.dart';

/// Overridden in `main()` (network or bundled sample) and in tests.
final Provider<DigestRepository> digestRepositoryProvider =
    Provider<DigestRepository>(
  (Ref ref) =>
      throw UnimplementedError('digestRepositoryProvider not overridden'),
);

@immutable
class DigestState {
  const DigestState({
    this.loaded,
    this.initialising = true,
    this.refreshing = false,
    this.lastFailure,
  });

  final LoadedDigest? loaded;

  /// The cache has not been read yet.
  final bool initialising;
  final bool refreshing;

  /// Why the most recent refresh failed; null once one succeeds.
  final RefreshFailureKind? lastFailure;

  Digest? get digest => loaded?.digest;

  DigestState copyWith({
    LoadedDigest? loaded,
    bool? initialising,
    bool? refreshing,
    RefreshFailureKind? lastFailure,
    bool clearFailure = false,
  }) =>
      DigestState(
        loaded: loaded ?? this.loaded,
        initialising: initialising ?? this.initialising,
        refreshing: refreshing ?? this.refreshing,
        lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      );
}

/// Cache first, then revalidate:
///
/// * launch: show the cached digest at once; fetch if there is none, or if
///   it is from before today (UTC) or was fetched more than 6 h ago;
/// * resume: the same check;
/// * pull-to-refresh: always fetch (still conditional on the ETag).
class DigestController extends Notifier<DigestState> {
  Future<void>? _inFlight;

  DigestRepository get _repo => ref.read(digestRepositoryProvider);

  @override
  DigestState build() {
    Future<void>.microtask(_start);
    return const DigestState();
  }

  Future<void> _start() async {
    if (!ref.mounted) return;
    LoadedDigest? cached;
    try {
      cached = await _repo.loadCached();
    } on Object catch (e) {
      // Anything unexpected reading the cache (an asset or isolate failure,
      // a plugin error) is a cache miss, never an endless first-screen
      // spinner with no Retry (code review m4).
      debugPrint('Digest cache read failed: $e');
      cached = null;
    }
    if (!ref.mounted) return;
    state = state.copyWith(loaded: cached, initialising: false);
    if (cached == null || _repo.needsRevalidation(cached)) {
      await refresh();
    }
  }

  /// Called when the app returns to the foreground.
  Future<void> onResumed() async {
    if (state.initialising) return;
    final LoadedDigest? current = state.loaded;
    if (current == null || _repo.needsRevalidation(current)) {
      await refresh();
    }
  }

  /// Fetches now. Concurrent calls share one request.
  Future<void> refresh() => _inFlight ??= _refresh().whenComplete(() {
        _inFlight = null;
      });

  Future<void> _refresh() async {
    state = state.copyWith(refreshing: true);
    RefreshOutcome outcome;
    try {
      outcome = await _repo.refresh(current: state.loaded);
    } on Object catch (e) {
      // Anything unexpected still ends the refresh: a stuck `refreshing`
      // is an endless spinner with no Retry on a first launch (F1). The
      // cached digest, if any, stays on screen under the failure banner.
      debugPrint('Digest refresh failed: $e');
      outcome = const RefreshFailed(RefreshFailureKind.server);
    }
    if (!ref.mounted) return;
    state = switch (outcome) {
      RefreshUpdated(:final LoadedDigest loaded) ||
      RefreshUnchanged(:final LoadedDigest loaded) =>
        state.copyWith(loaded: loaded, refreshing: false, clearFailure: true),
      RefreshFailed(:final RefreshFailureKind kind) =>
        state.copyWith(refreshing: false, lastFailure: kind),
    };
  }
}

final NotifierProvider<DigestController, DigestState> digestControllerProvider =
    NotifierProvider<DigestController, DigestState>(DigestController.new);
