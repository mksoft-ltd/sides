import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/message_state.dart';
import '../../../ads/presentation/ad_banner_slot.dart';
import '../../../digest/domain/digest.dart';
import '../../../digest/presentation/providers/digest_controller.dart';
import '../widgets/story_detail_view.dart';

class StoryDetailScreen extends ConsumerWidget {
  const StoryDetailScreen({
    super.key,
    required this.storyId,
    this.initialAxis = PerspectiveAxis.lean,
  });
  final String storyId;
  final PerspectiveAxis initialAxis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Digest? digest =
        ref.watch(digestControllerProvider.select((DigestState s) => s.digest));
    final Story? story = digest?.story(storyId);
    return Scaffold(
      appBar: AppBar(title: Text(story == null ? 'Story' : 'Story ${story.rank}')),
      body: digest == null || story == null
          ? const MessageState(
              icon: Icons.article_outlined,
              title: 'Story not available',
              message: 'This story isn\'t in the current digest any more. '
                  'Go back to see today\'s stories.',
            )
          : StoryDetailView(
              story: story,
              digest: digest,
              initialAxis: initialAxis,
            ),
      bottomNavigationBar: story == null ? null : const AdBannerSlot(),
    );
  }
}
