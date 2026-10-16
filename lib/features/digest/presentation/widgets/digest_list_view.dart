import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../data/digest_repository.dart';
import '../../domain/digest.dart';
import '../providers/digest_controller.dart';
import 'story_card.dart';

/// The digest list without a scaffold, so a tablet layout (phase 5) can put
/// it in a master pane. [onOpenStory] decides what "open" means there.
class DigestListView extends ConsumerWidget {
  const DigestListView({
    super.key,
    required this.onOpenStory,
    this.selectedStoryId,
    this.scrollController,
  });

  final ValueChanged<Story> onOpenStory;

  /// Highlighted story in master-detail; unused on phones.
  final String? selectedStoryId;

  /// Lets the tablet layout keep the list's scroll position when the
  /// selection moves between routes.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DigestState state = ref.watch(digestControllerProvider);
    final DigestController controller =
        ref.read(digestControllerProvider.notifier);
    final LoadedDigest? loaded = state.loaded;

    if (loaded == null) {
      if (state.initialising || state.refreshing || state.lastFailure == null) {
        return const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading today\'s digest',
          ),
        );
      }
      final ({String title, String message}) copy =
          _failureCopy(state.lastFailure!, hasCache: false);
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: MessageState(
          icon: state.lastFailure == RefreshFailureKind.offline
              ? Icons.cloud_off_outlined
              : Icons.error_outline,
          title: copy.title,
          message: copy.message,
          actionLabel: 'Retry',
          onAction: controller.refresh,
        ),
      );
    }

    final Digest digest = loaded.digest;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: digest.stories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return _DigestHeader(
              digest: digest,
              failure: state.lastFailure,
            );
          }
          final Story story = digest.stories[i - 1];
          return StoryCard(
            story: story,
            selected: story.id == selectedStoryId,
            onTap: () => onOpenStory(story),
          );
        },
      ),
    );
  }
}

({String title, String message}) _failureCopy(
  RefreshFailureKind kind, {
  required bool hasCache,
}) {
  final String saved = hasCache ? ' Showing the digest saved on this phone.' : '';
  return switch (kind) {
    RefreshFailureKind.offline => (
        title: 'You\'re offline',
        message: hasCache
            ? 'Couldn\'t check for a newer digest.$saved'
            : 'Today\'s digest will appear once you\'re connected. '
                'Pull down or tap Retry.',
      ),
    RefreshFailureKind.unsupportedVersion => (
        title: 'Update Sides',
        message: 'A newer digest format is available. Update the app to read '
            'it.$saved',
      ),
    RefreshFailureKind.server || RefreshFailureKind.invalid => (
        title: 'Digest not available',
        message: 'Today\'s digest couldn\'t be loaded right now.'
            '${hasCache ? saved : ' Please try again shortly.'}',
      ),
  };
}

class _DigestHeader extends StatelessWidget {
  const _DigestHeader({required this.digest, required this.failure});
  final Digest digest;
  final RefreshFailureKind? failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? day = DateTime.tryParse(digest.date);
    final String dayLabel =
        day == null ? digest.date : DateFormat('EEEE d MMMM y').format(day);
    final String updated = DateFormat('d MMM y, HH:mm')
        .format(digest.generatedAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (failure != null) ...<Widget>[
          _NoticeBanner(
            text: _failureCopy(failure!, hasCache: true).message,
            offline: failure == RefreshFailureKind.offline,
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(dayLabel, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 4),
        Text(
          'Last updated $updated · ${digest.stories.length} top stories',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          Copy.digestIntro,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text, required this.offline});
  final String text;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(offline ? Icons.cloud_off_outlined : Icons.info_outline,
              size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
