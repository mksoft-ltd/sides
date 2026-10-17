import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../digest/domain/digest.dart';
import '../../digest/presentation/providers/digest_controller.dart';
import '../data/archive_repository.dart';
import '../data/topic_repository.dart';
import '../domain/search.dart';

/// Overridden in `main()` and in tests.
final Provider<ArchiveRepository> archiveRepositoryProvider =
    Provider<ArchiveRepository>(
  (Ref ref) =>
      throw UnimplementedError('archiveRepositoryProvider not overridden'),
);

final Provider<TopicRepository> topicRepositoryProvider =
    Provider<TopicRepository>(
  (Ref ref) => throw UnimplementedError('topicRepositoryProvider not overridden'),
);

/// Digests that are not today's: archive days and topic results, by handle
/// (`archive:<date>`, `topic:<n>`), so a story page can be opened from them
/// through `/d/:handle/story/:id`.
final NotifierProvider<ExtraDigests, Map<String, Digest>> extraDigestsProvider =
    NotifierProvider<ExtraDigests, Map<String, Digest>>(ExtraDigests.new);

class ExtraDigests extends Notifier<Map<String, Digest>> {
  @override
  Map<String, Digest> build() => const <String, Digest>{};

  void put(String handle, Digest digest) =>
      state = <String, Digest>{...state, handle: digest};

  static String archiveHandle(String date) => 'archive:$date';
}

/// The steps of one search, cheapest first. The progress panel lists them.
enum SearchStep {
  /// Today's digest and the archive days saved on this phone. No network.
  phone,

  /// The rest of the last two weeks, downloaded once and saved.
  archive,

  /// Whether another reader already had today's coverage compared.
  shared,

  /// A new comparison of today's coverage (only when today's digest has no
  /// story for these words).
  compare,
}

enum StepStatus { waiting, running, done, skipped }

enum TopicPhase { none, ready, noMatch, capped, rateLimited, failed }

@immutable
class SearchState {
  const SearchState({
    this.query = '',
    this.searching = false,
    this.hits = const <SearchHit>[],
    this.daysSearched = 0,
    this.archiveUnavailable = false,
    this.steps = const <SearchStep, StepStatus>{},
    this.phoneHits = 0,
    this.compareStartedAt,
    this.outletsPolled = 0,
    this.topicPhase = TopicPhase.none,
    this.topicHandle,
    this.topicStory,
    this.topicCached = false,
    this.topicMessage,
  });

  final String query;
  final bool searching;
  final List<SearchHit> hits;

  /// How many digests (today's plus archive days) were searched.
  final int daysSearched;

  /// The archive index could not be reached; only saved days were searched.
  final bool archiveUnavailable;

  /// Where each step stands, for the progress panel.
  final Map<SearchStep, StepStatus> steps;

  /// Stories found on the phone alone (shown in the panel).
  final int phoneHits;

  /// When a new comparison started (drives the estimated progress bar).
  final DateTime? compareStartedAt;

  /// How many outlets today's digest drew on (for the explanation).
  final int outletsPolled;

  final TopicPhase topicPhase;
  final String? topicHandle;
  final Story? topicStory;
  final bool topicCached;
  final String? topicMessage;

  bool get hasQuery => queryTerms(query).isNotEmpty;

  StepStatus status(SearchStep s) => steps[s] ?? StepStatus.waiting;

  SearchState copyWith({
    String? query,
    bool? searching,
    List<SearchHit>? hits,
    int? daysSearched,
    bool? archiveUnavailable,
    Map<SearchStep, StepStatus>? steps,
    int? phoneHits,
    DateTime? compareStartedAt,
    int? outletsPolled,
    TopicPhase? topicPhase,
    String? topicHandle,
    Story? topicStory,
    bool? topicCached,
    String? topicMessage,
  }) =>
      SearchState(
        query: query ?? this.query,
        searching: searching ?? this.searching,
        hits: hits ?? this.hits,
        daysSearched: daysSearched ?? this.daysSearched,
        archiveUnavailable: archiveUnavailable ?? this.archiveUnavailable,
        steps: steps ?? this.steps,
        phoneHits: phoneHits ?? this.phoneHits,
        compareStartedAt: compareStartedAt ?? this.compareStartedAt,
        outletsPolled: outletsPolled ?? this.outletsPolled,
        topicPhase: topicPhase ?? this.topicPhase,
        topicHandle: topicHandle ?? this.topicHandle,
        topicStory: topicStory ?? this.topicStory,
        topicCached: topicCached ?? this.topicCached,
        topicMessage: topicMessage ?? this.topicMessage,
      );
}

/// One search, cheapest source first, with results streaming in:
///
/// 1. **phone**: today's digest, the archive days saved on the phone and any
///    comparison this phone already received today. Instant, offline.
/// 2. **archive** and **shared**, in parallel: download the archive days not
///    yet saved, and ask the topic service's shared cache (free).
/// 3. **compare**: only when today's digest has no story for the words and
///    nobody has compared them yet today, start a new comparison. The
///    service refuses cheaply when fewer than three outlets match and caps
///    new comparisons per day.
class SearchController extends Notifier<SearchState> {
  static const int archiveDays = 14;
  int _serial = 0;

  @override
  SearchState build() => const SearchState();

  void _step(SearchStep s, StepStatus status) => state = state.copyWith(
        steps: <SearchStep, StepStatus>{...state.steps, s: status},
      );

  Future<void> search(String query) async {
    final int serial = ++_serial;
    bool stale() => serial != _serial;
    state = SearchState(query: query, searching: true);
    if (!state.hasQuery) {
      state = state.copyWith(searching: false);
      return;
    }
    final ArchiveRepository archive = ref.read(archiveRepositoryProvider);
    final TopicRepository topic = ref.read(topicRepositoryProvider);
    final Digest? today = ref.read(digestControllerProvider).digest;
    final Map<String, Digest> byDate = <String, Digest>{
      if (today != null) today.date: today, // ignore: use_null_aware_elements
    };
    state = state.copyWith(outletsPolled: today?.meta.outletsPolled ?? 0);

    void publish() {
      state = state.copyWith(
        hits: searchStories(
          byDate.values.toList()
            ..sort((Digest a, Digest b) => b.date.compareTo(a.date)),
          query,
        ),
        daysSearched: byDate.length,
      );
    }

    // 1. On the phone.
    _step(SearchStep.phone, StepStatus.running);
    final List<ArchiveEntry> saved = await archive.index(online: false);
    for (final ArchiveEntry e in saved.take(archiveDays)) {
      if (byDate.containsKey(e.date)) continue;
      final Digest? d = await archive.digest(e.date, online: false);
      if (stale()) return;
      if (d != null) _addArchive(byDate, d);
    }
    if (stale()) return;
    publish();
    state = state.copyWith(phoneHits: state.hits.length);
    final TopicReady? onPhone = topic.onPhone(query);
    if (onPhone != null) _showTopic(onPhone);
    _step(SearchStep.phone, StepStatus.done);

    // 2. Online: the rest of the archive and the shared cache, together.
    _step(SearchStep.archive, StepStatus.running);
    _step(
      SearchStep.shared,
      onPhone != null ? StepStatus.skipped : StepStatus.running,
    );
    final Future<TopicOutcome?> peek =
        onPhone != null ? Future<TopicOutcome?>.value(null) : topic.peek(query);
    final List<ArchiveEntry> index = await archive.index();
    if (stale()) return;
    for (final ArchiveEntry e in index.take(archiveDays)) {
      if (byDate.containsKey(e.date)) continue;
      final Digest? d = await archive.digest(e.date);
      if (stale()) return;
      if (d != null) {
        _addArchive(byDate, d);
        publish(); // stream each day's hits in as it arrives
      }
    }
    state = state.copyWith(archiveUnavailable: index.isEmpty);
    _step(SearchStep.archive, StepStatus.done);
    final TopicOutcome? shared = await peek;
    if (stale()) return;
    if (onPhone == null) _step(SearchStep.shared, StepStatus.done);
    if (shared != null) _applyTopic(shared);

    // 3. A new comparison, only when nothing covers today yet.
    final bool todayCovered = today != null &&
        state.hits.any((SearchHit h) => h.digest.date == today.date);
    final bool haveTopic = state.topicPhase != TopicPhase.none;
    if (todayCovered || haveTopic) {
      _step(SearchStep.compare, StepStatus.skipped);
    } else {
      _step(SearchStep.compare, StepStatus.running);
      state = state.copyWith(compareStartedAt: DateTime.now());
      final TopicOutcome outcome = await topic.analyse(query);
      if (stale()) return;
      _applyTopic(outcome);
      _step(SearchStep.compare, StepStatus.done);
    }
    state = state.copyWith(searching: false);
  }

  /// Runs the search again (the "Try again" after a failed comparison).
  Future<void> retry() => search(state.query);

  void _addArchive(Map<String, Digest> byDate, Digest d) {
    byDate[d.date] = d;
    ref
        .read(extraDigestsProvider.notifier)
        .put(ExtraDigests.archiveHandle(d.date), d);
  }

  void _showTopic(TopicReady r) {
    final String handle = 'topic:${r.digest.stories.first.id}';
    ref.read(extraDigestsProvider.notifier).put(handle, r.digest);
    state = state.copyWith(
      topicPhase: TopicPhase.ready,
      topicHandle: handle,
      topicStory: r.digest.stories.first,
      topicCached: r.cached,
    );
  }

  void _applyTopic(TopicOutcome o) {
    switch (o) {
      case TopicReady():
        _showTopic(o);
      case TopicNoMatch():
        state = state.copyWith(topicPhase: TopicPhase.noMatch);
      case TopicCapped():
        state = state.copyWith(topicPhase: TopicPhase.capped);
      case TopicRateLimited():
        state = state.copyWith(topicPhase: TopicPhase.rateLimited);
      case TopicFailed(:final String message):
        state = state.copyWith(
          topicPhase: TopicPhase.failed,
          topicMessage: message,
        );
      case TopicMiss():
        break;
    }
  }
}

final NotifierProvider<SearchController, SearchState> searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
