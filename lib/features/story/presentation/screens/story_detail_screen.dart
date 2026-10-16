import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/copy.dart';
import '../../../../shared/widgets/message_state.dart';
import '../../../ads/presentation/ad_banner_slot.dart';
import '../../../digest/domain/digest.dart';
import '../../../digest/presentation/providers/digest_controller.dart';
import '../providers/story_view_controller.dart';
import '../widgets/story_detail_view.dart';

/// The phone story page: "n of N" in the app bar with previous / next
/// story, the story body, the banner slot at the bottom edge.
class StoryDetailScreen extends ConsumerWidget {
  const StoryDetailScreen({
    super.key,
    required this.storyId,
    this.initialAxis = PerspectiveAxis.lean,
  });
  final String storyId;
  final PerspectiveAxis initialAxis;

  static const Key previousKey = Key('previous-story');
  static const Key nextKey = Key('next-story');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Digest? digest =
        ref.watch(digestControllerProvider.select((DigestState s) => s.digest));
    final Story? story = digest?.story(storyId);
    final int index = digest == null || story == null
        ? -1
        : digest.stories.indexWhere((Story s) => s.id == story.id);

    /// Replaces this page with the neighbouring story, keeping the reader's
    /// axis; back still returns to the list.
    void goTo(Story next) {
      final PerspectiveAxis axis =
          ref.read(storyViewProvider(storyId)).axisOr(initialAxis);
      context.pushReplacement(Routes.story(next.id, axis: axis));
    }

    return Scaffold(
      appBar: AppBar(
        title: story == null || digest == null
            ? const Text('Story')
            : Text(
                Copy.storyPosition(story.rank, digest.stories.length),
                semanticsLabel: Copy.storyPositionSpoken(
                  story.rank,
                  digest.stories.length,
                ),
              ),
        actions: <Widget>[
          if (digest != null && story != null) ...<Widget>[
            IconButton(
              key: previousKey,
              tooltip: Copy.previousStory,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed:
                  index > 0 ? () => goTo(digest.stories[index - 1]) : null,
            ),
            IconButton(
              key: nextKey,
              tooltip: Copy.nextStory,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: index >= 0 && index < digest.stories.length - 1
                  ? () => goTo(digest.stories[index + 1])
                  : null,
            ),
          ],
        ],
      ),
      body: digest == null || story == null
          ? const MessageState(
              icon: Icons.article_outlined,
              title: 'Story not available',
              message: 'This story isn\'t in the current digest any more. '
                  'Go back to see today\'s stories.',
            )
          : StoryDetailView(
              // A fresh view (scrolled to the top) per story.
              key: ValueKey<String>('detail-${story.id}'),
              story: story,
              digest: digest,
              initialAxis: initialAxis,
            ),
      bottomNavigationBar: story == null ? null : const AdBannerSlot(),
    );
  }
}
