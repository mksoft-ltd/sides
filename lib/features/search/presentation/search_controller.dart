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

enum TopicPhase { idle, working, ready, noMatch, capped, rateLimited, failed }

@immutable
class SearchState {
  const SearchState({
    this.query = '',
    this.searching = false,
    this.hits = const <SearchHit>[],
    this.daysSearched = 0,
    this.archiveUnavailable = false,
    this.topicPhase = TopicPhase.idle,
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

  /// The archive index could not be reached; only cached days were searched.
  final bool archiveUnavailable;

  final TopicPhase topicPhase;
  final String? topicHandle;
  final Story? topicStory;
  final bool topicCached;
  final String? topicMessage;

  bool get hasQuery => queryTerms(query).isNotEmpty;

  SearchState copyWith({
    String? query,
    bool? searching,
    List<SearchHit>? hits,
    int? daysSearched,
    bool? archiveUnavailable,
    TopicPhase? topicPhase,
    String? topicHandle,
    Story? topicStory,
    bool? topicCached,
    String? topicMessage,
    bool clearTopic = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        searching: searching ?? this.searching,
        hits: hits ?? this.hits,
        daysSearched: daysSearched ?? this.daysSearched,
        archiveUnavailable: archiveUnavailable ?? this.archiveUnavailable,
        topicPhase: clearTopic ? TopicPhase.idle : (topicPhase ?? this.topicPhase),
        topicHandle: clearTopic ? null : (topicHandle ?? this.topicHandle),
        topicStory: clearTopic ? null : (topicStory ?? this.topicStory),
        topicCached: clearTopic ? false : (topicCached ?? this.topicCached),
        topicMessage: clearTopic ? null : (topicMessage ?? this.topicMessage),
      );
}

/// Search = today's digest + the last [archiveDays] days of the archive,
/// matched on the device. A topic analysis is a separate, explicit step.
class SearchController extends Notifier<SearchState> {
  static const int archiveDays = 14;
  int _serial = 0;
  int _topicSerial = 0;

  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    final int serial = ++_serial;
    state = state.copyWith(
      query: query,
      searching: true,
      hits: const <SearchHit>[],
      clearTopic: true,
    );
    if (!state.hasQuery) {
      state = state.copyWith(searching: false, daysSearched: 0);
      return;
    }
    final ArchiveRepository archive = ref.read(archiveRepositoryProvider);
    final Digest? today = ref.read(digestControllerProvider).digest;
    final List<Digest> digests = <Digest>[?today];
    final List<ArchiveEntry> index = await archive.index();
    if (serial != _serial) return;
    final List<String> dates = index
        .map((ArchiveEntry e) => e.date)
        .where((String d) => d != today?.date)
        .take(archiveDays)
        .toList();
    for (final String d in dates) {
      final Digest? digest = await archive.digest(d);
      if (serial != _serial) return;
      if (digest != null) {
        digests.add(digest);
        ref.read(extraDigestsProvider.notifier).put(
              ExtraDigests.archiveHandle(d),
              digest,
            );
      }
      // Show what is found so far: the archive can take a few seconds.
      state = state.copyWith(hits: searchStories(digests, query));
    }
    state = state.copyWith(
      searching: false,
      hits: searchStories(digests, query),
      daysSearched: digests.length,
      archiveUnavailable: index.isEmpty,
    );
  }

  /// Asks the topic service for today's coverage of the current query.
  Future<void> analyseTopic() async {
    if (!state.hasQuery || state.topicPhase == TopicPhase.working) return;
    final int serial = ++_topicSerial;
    final String query = state.query;
    state = state.copyWith(topicPhase: TopicPhase.working, topicMessage: null);
    final TopicOutcome outcome =
        await ref.read(topicRepositoryProvider).analyse(query);
    if (serial != _topicSerial || query != state.query) return;
    switch (outcome) {
      case TopicReady(:final Digest digest, :final bool cached):
        final String handle = 'topic:${digest.stories.first.id}';
        ref.read(extraDigestsProvider.notifier).put(handle, digest);
        state = state.copyWith(
          topicPhase: TopicPhase.ready,
          topicHandle: handle,
          topicStory: digest.stories.first,
          topicCached: cached,
        );
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
    }
  }
}

final NotifierProvider<SearchController, SearchState> searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
