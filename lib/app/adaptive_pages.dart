import 'package:flutter/material.dart';

import '../core/layout/breakpoints.dart';
import '../features/digest/presentation/screens/digest_list_screen.dart';
import '../features/digest/presentation/screens/master_detail_screen.dart';
import '../features/story/presentation/screens/story_detail_screen.dart';
import '../features/story/presentation/widgets/story_detail_view.dart';

/// `/`: the phone list, or master-detail with story 1 selected at tablet
/// widths. Decided on every build, so rotation and window resizing switch
/// layouts live; the selection (route) and axis (provider) carry over.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) =>
      LayoutSize.of(context) == LayoutSize.compact
      ? const DigestListScreen()
      : const MasterDetailScreen();
}

/// `/story/:id`: the phone story page, or master-detail with that story.
class StoryPage extends StatelessWidget {
  const StoryPage({
    super.key,
    required this.storyId,
    required this.initialAxis,
  });

  final String storyId;
  final PerspectiveAxis initialAxis;

  @override
  Widget build(BuildContext context) =>
      LayoutSize.of(context) == LayoutSize.compact
      ? StoryDetailScreen(storyId: storyId, initialAxis: initialAxis)
      : MasterDetailScreen(selectedStoryId: storyId, initialAxis: initialAxis);
}
